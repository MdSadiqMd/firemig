import { attachSocket, startHeartbeat } from "./connect.js";
import { dispatchFrame, PendingReplies } from "./pending.js";
import {
    abortError,
    defaultWebSocketFactory,
    isPhoenixMessage,
    messageText,
    OPEN,
    type PhoenixMessage,
    type WebSocketFactory,
    type WebSocketLike,
} from "./protocol.js";

/** One multiplexed Phoenix socket: connect, join topics, push refs, resolve replies. */
export class PhoenixSocket {
    private socket: WebSocketLike | undefined;
    private connecting: Promise<void> | undefined;
    private heartbeat: ReturnType<typeof setInterval> | undefined;
    private nextRef = 1;
    private readonly pending = new PendingReplies();
    private readonly joinedTopics = new Map<string, string>();
    private readonly joiningTopics = new Map<string, Promise<string>>();
    private readonly eventListeners = new Set<(message: PhoenixMessage) => void>();

    constructor(
        private readonly url: () => string,
        private readonly webSocketFactory: WebSocketFactory = defaultWebSocketFactory,
    ) {}

    ref(): string {
        return String(this.nextRef++);
    }

    close(): void {
        const socket = this.socket;
        if (socket === undefined) return;
        this.disconnect(socket, new Error("Firemig WebSocket client closed"));
        socket.close(1000, "client closed");
    }

    async join(topic: string): Promise<string> {
        const joined = this.joinedTopics.get(topic);
        if (joined !== undefined) return joined;

        const joining = this.joiningTopics.get(topic);
        if (joining !== undefined) return await joining;

        const promise = (async () => {
            await this.connect();
            const ref = this.ref();
            await this.push([ref, ref, topic, "phx_join", {}]);
            this.joinedTopics.set(topic, ref);
            return ref;
        })();
        this.joiningTopics.set(topic, promise);
        try {
            return await promise;
        } finally {
            if (this.joiningTopics.get(topic) === promise) this.joiningTopics.delete(topic);
        }
    }

    push<T>(message: PhoenixMessage, signal?: AbortSignal): Promise<T> {
        const ref = message[1];
        if (ref === null) throw new Error("Phoenix request ref is required");
        if (signal?.aborted === true) return Promise.reject(abortError(signal));
        const socket = this.socket;
        if (socket?.readyState !== OPEN)
            return Promise.reject(new Error("Firemig WebSocket is not connected"));

        return new Promise<T>((resolve, reject) => {
            const pending = this.pending.add(
                ref,
                (response) => resolve(response as T),
                reject,
                signal,
            );
            try {
                socket.send(JSON.stringify(message));
            } catch (error) {
                this.pending.discard(ref, pending);
                reject(error instanceof Error ? error : new Error(String(error)));
            }
        });
    }

    subscribe(listener: (message: PhoenixMessage) => void): () => void {
        this.eventListeners.add(listener);
        return () => this.eventListeners.delete(listener);
    }

    private async connect(): Promise<void> {
        if (this.socket?.readyState === OPEN) return;
        if (this.connecting !== undefined) return await this.connecting;

        const socket = this.webSocketFactory(this.url());
        this.socket = socket;
        const connecting = new Promise<void>((resolve, reject) => {
            attachSocket(
                socket,
                {
                    isCurrent: (candidate) => this.socket === candidate,
                    onOpen: (opened) => {
                        this.heartbeat = startHeartbeat(
                            opened,
                            (candidate) => this.socket === candidate,
                            () => this.ref(),
                        );
                    },
                    onMessage: (data) => this.handleMessage(socket, data),
                    onFailure: (failed, error) => this.disconnect(failed, error),
                },
                resolve,
                reject,
            );
        });
        this.connecting = connecting;
        try {
            await connecting;
        } finally {
            if (this.connecting === connecting) this.connecting = undefined;
        }
    }

    private handleMessage(socket: WebSocketLike, data: unknown): void {
        dispatchFrame(this.pending, data, (message) => {
            for (const listener of this.eventListeners) listener(message);
        }).catch((error: unknown) => {
            const failure = error instanceof Error ? error : new Error(String(error));
            this.disconnect(socket, failure);
            socket.close(1002, "invalid Phoenix frame");
        });
    }

    private disconnect(socket: WebSocketLike, error: Error): void {
        if (this.socket !== socket) return;
        this.socket = undefined;
        this.joinedTopics.clear();
        if (this.heartbeat !== undefined) {
            clearInterval(this.heartbeat);
            this.heartbeat = undefined;
        }
        this.pending.rejectAll(error);
    }
}
