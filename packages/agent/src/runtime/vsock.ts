import { createConnection } from "node:net";
import type { Duplex } from "node:stream";
import { randomUUID } from "node:crypto";
import { ErrorCode, FiremigError } from "@firemig/common";

export type VsockConnector = (path: string) => Promise<Duplex>;

export const nodeVsockConnector: VsockConnector = (path) =>
    new Promise((resolve, reject) => {
        const socket = createConnection(path);
        socket.once("connect", () => resolve(socket));
        socket.once("error", reject);
    });

export interface GuestRpcResponse<T = unknown> {
    id: string;
    ok: boolean;
    result?: T;
    error?: { message: string; code?: string };
}

export class VsockGuestClient {
    constructor(
        private readonly socketPath: string,
        private readonly port = 5000,
        private readonly connect: VsockConnector = nodeVsockConnector,
        private readonly timeoutMs = 10_000,
    ) {}

    async call<T>(
        method: string,
        params: Record<string, unknown> = {},
        timeoutMs = this.timeoutMs,
    ): Promise<T> {
        const socket = await this.connect(this.socketPath);
        const timeout = AbortSignal.timeout(timeoutMs);
        const onTimeout = () => socket.destroy(new Error("Guest agent timed out"));
        timeout.addEventListener("abort", onTimeout, { once: true });
        try {
            socket.write(`CONNECT ${this.port}\n`);
            const handshake = await readLine(socket);
            if (!/^OK(?: \d+)?$/.test(handshake))
                throw new Error(`Invalid vsock handshake: ${handshake}`);
            const id = randomUUID();
            socket.write(`${JSON.stringify({ id, method, params })}\n`);
            const response = JSON.parse(await readLine(socket)) as GuestRpcResponse<T>;
            if (response.id !== id) throw new Error("Guest agent returned a mismatched request id");
            if (!response.ok) {
                throw new FiremigError({
                    code: response.error?.code ?? ErrorCode.GuestAgent,
                    message: response.error?.message ?? "Guest agent request failed",
                    retryable: false,
                });
            }
            return response.result as T;
        } finally {
            timeout.removeEventListener("abort", onTimeout);
            socket.destroy();
        }
    }

    ready(timeoutMs?: number): Promise<{ bootId: string }> {
        return this.call("ready", {}, timeoutMs);
    }

    runCommand(params: Record<string, unknown>): Promise<Record<string, unknown>> {
        return this.call("run_command", params);
    }

    writeFile(params: Record<string, unknown>): Promise<Record<string, unknown>> {
        return this.call("write_file", params);
    }

    syncClock(): Promise<void> {
        return this.call("sync_clock", { unixTimeNs: Date.now() * 1_000_000 });
    }
}

function readLine(stream: Duplex): Promise<string> {
    return new Promise((resolve, reject) => {
        let buffered = Buffer.alloc(0);
        const onData = (chunk: Buffer) => {
            buffered = Buffer.concat([buffered, chunk]);
            const newline = buffered.indexOf(0x0a);
            if (newline < 0) return;
            cleanup();
            const remainder = buffered.subarray(newline + 1);
            if (remainder.length > 0) stream.unshift(remainder);
            resolve(buffered.subarray(0, newline).toString("utf8").replace(/\r$/, ""));
        };
        const onError = (error: Error) => {
            cleanup();
            reject(error);
        };
        const onEnd = () => {
            cleanup();
            reject(new Error("Connection ended before a complete line"));
        };
        const cleanup = () => {
            stream.off("data", onData);
            stream.off("error", onError);
            stream.off("end", onEnd);
        };
        stream.on("data", onData);
        stream.once("error", onError);
        stream.once("end", onEnd);
    });
}
