import {
    HEARTBEAT_INTERVAL_MS,
    OPEN,
    type PhoenixMessage,
    type WebSocketLike,
} from "./protocol.js";

export interface SocketHandlers {
    /** False once a newer socket has replaced this one, so late events are ignored. */
    isCurrent: (socket: WebSocketLike) => boolean;
    onOpen: (socket: WebSocketLike) => void;
    onMessage: (data: unknown) => void;
    onFailure: (socket: WebSocketLike, error: Error) => void;
}

export function attachSocket(
    socket: WebSocketLike,
    handlers: SocketHandlers,
    resolve: () => void,
    reject: (error: Error) => void,
): void {
    let opened = false;
    socket.addEventListener("open", () => {
        if (!handlers.isCurrent(socket)) return;
        opened = true;
        handlers.onOpen(socket);
        resolve();
    });
    socket.addEventListener("message", (event) => {
        handlers.onMessage(event.data);
    });
    socket.addEventListener("error", () => {
        const error = new Error("Firemig WebSocket connection failed");
        if (!opened) reject(error);
        handlers.onFailure(socket, error);
        if (socket.readyState < OPEN + 1) socket.close();
    });
    socket.addEventListener("close", (event) => {
        const suffix = event.reason === undefined || event.reason === "" ? "" : `: ${event.reason}`;
        const error = new Error(`Firemig WebSocket closed${suffix}`);
        if (!opened) reject(error);
        handlers.onFailure(socket, error);
    });
}

export function startHeartbeat(
    socket: WebSocketLike,
    isCurrent: (socket: WebSocketLike) => boolean,
    ref: () => string,
): ReturnType<typeof setInterval> {
    const timer = setInterval(() => {
        if (!isCurrent(socket) || socket.readyState !== OPEN) return;
        const heartbeat: PhoenixMessage = [null, ref(), "phoenix", "heartbeat", {}];
        socket.send(JSON.stringify(heartbeat));
    }, HEARTBEAT_INTERVAL_MS);
    timer.unref?.();
    return timer;
}
