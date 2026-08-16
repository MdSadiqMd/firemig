import type { CommandResult, RunCommandRequest } from "@firemig/common";
import {
    abortError,
    channelError,
    defaultWebSocketFactory,
    type PhoenixMessage,
    type WebSocketFactory,
} from "./phoenix/protocol.js";
import { PhoenixSocket } from "./phoenix/socket.js";

export * from "./phoenix/protocol.js";
export { PhoenixSocket } from "./phoenix/socket.js";

export class PhoenixCommandTransport {
    private readonly socket: PhoenixSocket;

    constructor(
        private readonly baseUrl: string,
        private readonly userId: string,
        private readonly token: string | undefined,
        webSocketFactory: WebSocketFactory = defaultWebSocketFactory,
    ) {
        this.socket = new PhoenixSocket(() => this.socketUrl(), webSocketFactory);
    }

    async runCommand(
        sandboxId: string,
        request: RunCommandRequest,
        idempotencyKey: string,
        signal?: AbortSignal,
        awaitCompletion = false,
    ): Promise<CommandResult> {
        const topic = `sandbox:${sandboxId}:${this.userId}`;
        const joinRef = await this.socket.join(topic);
        const message: PhoenixMessage = [
            joinRef,
            this.socket.ref(),
            topic,
            "command",
            { commandId: idempotencyKey, idempotencyKey, payload: request },
        ];
        if (!awaitCompletion) return await this.socket.push<CommandResult>(message, signal);

        const completion = this.commandCompletion(topic, idempotencyKey);
        try {
            const accepted = await this.socket.push<CommandResult>(message, signal);
            if (accepted.queued !== true) return accepted;
            const result = await waitForCompletion(completion.promise, signal);
            return { ...result, commandId: idempotencyKey, queued: true };
        } finally {
            completion.cancel();
        }
    }

    close(): void {
        this.socket.close();
    }

    private commandCompletion(
        topic: string,
        commandId: string,
    ): { promise: Promise<CommandResult>; cancel: () => void } {
        let cancel: () => void = () => undefined;
        const promise = new Promise<CommandResult>((resolve, reject) => {
            const unsubscribe = this.socket.subscribe((message) => {
                if (message[2] !== topic || message[3] !== "command_result") return;
                const payload = commandEvent(message[4]);
                if (payload?.commandId !== commandId) return;
                if (payload.status === "failed") reject(channelError(payload.error));
                else if (payload.status === "done")
                    resolve(payload.result ?? { commandId: payload.commandId });
            });
            cancel = unsubscribe;
        });
        return { promise, cancel };
    }

    private socketUrl(): string {
        const url = new URL("/socket/websocket", this.baseUrl);
        url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
        url.searchParams.set("vsn", "2.0.0");
        url.searchParams.set("userId", this.userId);
        if (this.token !== undefined) url.searchParams.set("token", this.token);
        return url.toString();
    }
}

interface CommandEvent {
    commandId: string;
    status: string;
    result?: CommandResult;
    error?: unknown;
}

function commandEvent(value: unknown): CommandEvent | undefined {
    if (typeof value !== "object" || value === null) return undefined;
    const event = value as Partial<CommandEvent>;
    if (typeof event.commandId !== "string" || typeof event.status !== "string") return undefined;
    return event as CommandEvent;
}

function waitForCompletion<T>(completion: Promise<T>, signal?: AbortSignal): Promise<T> {
    if (signal === undefined) return completion;
    if (signal.aborted) return Promise.reject(abortError(signal));
    return new Promise((resolve, reject) => {
        const onAbort = () => {
            signal.removeEventListener("abort", onAbort);
            reject(abortError(signal));
        };
        signal.addEventListener("abort", onAbort, { once: true });
        completion.then(
            (value) => {
                signal.removeEventListener("abort", onAbort);
                resolve(value);
            },
            (error: unknown) => {
                signal.removeEventListener("abort", onAbort);
                reject(error);
            },
        );
    });
}
