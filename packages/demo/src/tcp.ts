import { createConnection, type Socket } from "node:net";
import { parseCounterEvent, type ObservedCounterEvent } from "./validator.js";

export type SocketFactory = (port: number, host: string) => Socket;

export class RawTcpCollector {
    readonly observations: ObservedCounterEvent[] = [];
    readonly parseErrors: Error[] = [];
    private socket: Socket | undefined;
    private buffer = "";
    private connectAttempts = 0;
    private readonly waiters = new Set<() => void>();

    constructor(
        private readonly host: string,
        private readonly port: number,
        private readonly socketFactory: SocketFactory = (port, host) =>
            createConnection(port, host),
        private readonly now: () => number = Date.now,
    ) {}

    get reconnectCount(): number {
        return Math.max(0, this.connectAttempts - 1);
    }

    connect(): Promise<void> {
        if (this.socket !== undefined)
            return Promise.reject(new Error("RawTcpCollector uses exactly one connection"));
        this.connectAttempts += 1;
        const socket = this.socketFactory(this.port, this.host);
        this.socket = socket;
        socket.setNoDelay(true);
        socket.setKeepAlive(true);
        socket.on("data", (chunk: Buffer) => this.consume(chunk.toString("utf8")));
        return new Promise((resolve, reject) => {
            socket.once("connect", resolve);
            socket.once("error", reject);
        });
    }

    waitForCount(count: number, timeoutMs: number): Promise<void> {
        if (this.observations.length >= count) return Promise.resolve();
        return new Promise((resolve, reject) => {
            const check = () => {
                if (this.observations.length < count) return;
                cleanup();
                resolve();
            };
            const timeout = AbortSignal.timeout(timeoutMs);
            const onTimeout = () => {
                cleanup();
                reject(
                    new Error(
                        `Timed out waiting for ${count} counter events; received ${this.observations.length}`,
                    ),
                );
            };
            const cleanup = () => {
                timeout.removeEventListener("abort", onTimeout);
                this.waiters.delete(check);
            };
            timeout.addEventListener("abort", onTimeout, { once: true });
            this.waiters.add(check);
        });
    }

    close(): void {
        this.socket?.destroy();
    }

    private consume(chunk: string): void {
        this.buffer += chunk;
        while (true) {
            const newline = this.buffer.indexOf("\n");
            if (newline < 0) return;
            const line = this.buffer.slice(0, newline).trim();
            this.buffer = this.buffer.slice(newline + 1);
            if (line === "") continue;
            try {
                this.observations.push({
                    event: parseCounterEvent(line),
                    receivedAtMs: this.now(),
                });
            } catch (error) {
                this.parseErrors.push(error instanceof Error ? error : new Error(String(error)));
            }
            for (const waiter of this.waiters) waiter();
        }
    }
}
