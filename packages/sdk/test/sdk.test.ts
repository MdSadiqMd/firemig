import { describe, expect, it } from "vitest";
import { ErrorCode, MigrationPhase, SandboxState } from "@firemig/common";
import { FiremigClient, Migration, Sandbox } from "../src/client.js";
import { FencedError, IdempotencyConflictError } from "../src/errors.js";
import { parseSse } from "../src/sse.js";
import type { WebSocketEvent, WebSocketFactory, WebSocketLike } from "../src/websocket.js";

type WireMessage = [string | null, string | null, string, string, unknown];

class FakeWebSocket implements WebSocketLike {
    readyState = 0;
    readonly sent: WireMessage[] = [];
    readonly listeners = new Map<string, Array<(event: WebSocketEvent) => void>>();
    private readonly sentWaiters = new Map<number, (message: WireMessage) => void>();

    addEventListener(type: string, listener: (event: WebSocketEvent) => void): void {
        const listeners = this.listeners.get(type) ?? [];
        listeners.push(listener);
        this.listeners.set(type, listeners);
    }

    send(data: string): void {
        const message = JSON.parse(data) as WireMessage;
        this.sent.push(message);
        this.sentWaiters.get(this.sent.length - 1)?.(message);
        this.sentWaiters.delete(this.sent.length - 1);
    }

    close(_code?: number, reason?: string): void {
        this.readyState = 3;
        this.emit("close", reason === undefined ? {} : { reason });
    }

    open(): void {
        this.readyState = 1;
        this.emit("open", {});
    }

    reply(request: WireMessage, status: "ok" | "error", response: unknown): void {
        this.emit("message", {
            data: JSON.stringify([
                request[0],
                request[1],
                request[2],
                "phx_reply",
                { status, response },
            ]),
        });
    }

    broadcast(topic: string, event: string, payload: unknown): void {
        this.emit("message", { data: JSON.stringify([null, null, topic, event, payload]) });
    }

    waitForSent(index: number): Promise<WireMessage> {
        const message = this.sent[index];
        if (message !== undefined) return Promise.resolve(message);
        return new Promise((resolve) => this.sentWaiters.set(index, resolve));
    }

    private emit(type: string, event: WebSocketEvent): void {
        for (const listener of this.listeners.get(type) ?? []) listener(event);
    }
}

function fakeSocketFactory(): {
    factory: WebSocketFactory;
    sockets: FakeWebSocket[];
    urls: string[];
} {
    const sockets: FakeWebSocket[] = [];
    const urls: string[] = [];
    return {
        sockets,
        urls,
        factory: (url) => {
            urls.push(url);
            const socket = new FakeWebSocket();
            sockets.push(socket);
            return socket;
        },
    };
}

function sandbox(client: FiremigClient, id = "sandbox/1"): Sandbox {
    return new Sandbox(client, {
        id,
        region: "worker-a",
        worker: "worker-a",
        state: SandboxState.Running,
        epoch: 1,
        cpu: 1,
        memoryMb: 128,
        createdAt: "now",
    });
}

async function sentAt(socket: FakeWebSocket, index: number): Promise<WireMessage> {
    return await socket.waitForSent(index);
}

function stream(chunks: string[]): ReadableStream<Uint8Array> {
    const encoder = new TextEncoder();
    return new ReadableStream({
        start(controller) {
            for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
            controller.close();
        },
    });
}

describe("SSE parser", () => {
    it("handles chunk boundaries, CRLF, comments, and multiline data", async () => {
        const events = [];
        for await (const event of parseSse(
            stream([
                ": heartbeat\r\nid: 4\r\nevent: pro",
                'gress\r\ndata: {"a":\r',
                "\ndata: 1}\r\nretry: 250\r\n\r\n",
            ]),
        ))
            events.push(event);
        expect(events).toEqual([{ event: "progress", id: "4", data: '{"a":\n1}', retry: 250 }]);
    });
});

describe("SDK errors", () => {
    it("maps API envelopes to typed errors", async () => {
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "test-user",
            maxRetries: 0,
            fetch: async () =>
                new Response(
                    JSON.stringify({
                        error: { code: ErrorCode.Fenced, message: "stale", retryable: false },
                    }),
                    {
                        status: 409,
                        headers: { "content-type": "application/json" },
                    },
                ),
        });
        await expect(client.sandboxes.get("s1")).rejects.toBeInstanceOf(FencedError);
    });

    it("maps idempotency conflicts separately", async () => {
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "test-user",
            maxRetries: 0,
            fetch: async () =>
                new Response(
                    JSON.stringify({
                        error: {
                            code: ErrorCode.IdempotencyKeyConflict,
                            message: "reused",
                            retryable: false,
                        },
                    }),
                    { status: 409 },
                ),
        });
        await expect(
            client.sandboxes.create({ region: "a", cpu: 1, memoryMb: 128 }),
        ).rejects.toBeInstanceOf(IdempotencyConflictError);
    });
});

describe("migration watch", () => {
    it("reconnects SSE with Last-Event-ID and terminates on done", async () => {
        const requests: RequestInit[] = [];
        let call = 0;
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "test-user",
            fetch: async (_input, init) => {
                requests.push(init ?? {});
                call += 1;
                const body =
                    call === 1
                        ? 'id: 7\nevent: progress\ndata: {"phase":"TRANSFERRING","bytesTransferred":5,"bytesTotal":10,"ts":"now"}\n\n'
                        : 'id: 8\nevent: done\ndata: {"phase":"DONE","bytesTransferred":10,"bytesTotal":10,"ts":"now"}\n\n';
                return new Response(body, { headers: { "content-type": "text/event-stream" } });
            },
        });
        const migration = new Migration(client, {
            migrationId: "m1",
            sandboxId: "s1",
            phase: MigrationPhase.Preparing,
            bytesTransferred: 0,
            bytesTotal: 10,
        });
        const phases: MigrationPhase[] = [];
        for await (const progress of migration.watch({ pollIntervalMs: 0 }))
            phases.push(progress.phase);
        expect(phases).toEqual([MigrationPhase.Transferring, MigrationPhase.Done]);
        expect(new Headers(requests[1]!.headers).get("last-event-id")).toBe("7");
    });

    it("falls back to polling when SSE is unavailable", async () => {
        let call = 0;
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "test-user",
            fetch: async (_input, init) => {
                if (new Headers(init?.headers).get("accept") === "text/event-stream")
                    return new Response(null, { status: 404 });
                call += 1;
                return Response.json({
                    migrationId: "m1",
                    sandboxId: "s1",
                    phase: call === 1 ? "LOADING" : "DONE",
                    bytesTransferred: call === 1 ? 8 : 10,
                    bytesTotal: 10,
                });
            },
        });
        const migration = new Migration(client, {
            migrationId: "m1",
            sandboxId: "s1",
            phase: MigrationPhase.Preparing,
            bytesTransferred: 0,
            bytesTotal: 10,
        });
        const phases = [];
        for await (const progress of migration.watch({ pollIntervalMs: 0 }))
            phases.push(progress.phase);
        expect(phases).toEqual([MigrationPhase.Loading, MigrationPhase.Done]);
    });
});

describe("WebSocket commands", () => {
    it("connects with auth, joins, frames a direct command, and never calls HTTP commands", async () => {
        const fake = fakeSocketFactory();
        const httpPaths: string[] = [];
        const client = new FiremigClient({
            baseUrl: "https://api.example.test/v1/",
            userId: "user name",
            token: "a+b/token",
            webSocketFactory: fake.factory,
            fetch: async (input) => {
                httpPaths.push(String(input));
                throw new Error("unexpected HTTP request");
            },
        });

        const resultPromise = sandbox(client).commands.run(
            { command: "printf hello", cwd: "/tmp" },
            { idempotencyKey: "command-key" },
        );
        expect(fake.urls).toEqual([
            "wss://api.example.test/socket/websocket?vsn=2.0.0&userId=user+name&token=a%2Bb%2Ftoken",
        ]);

        const socket = fake.sockets[0]!;
        socket.open();
        const join = await sentAt(socket, 0);
        expect(join).toEqual(["1", "1", "sandbox:sandbox/1:user name", "phx_join", {}]);
        socket.reply(join, "ok", {});
        const command = await sentAt(socket, 1);
        expect(command).toEqual([
            "1",
            "2",
            "sandbox:sandbox/1:user name",
            "command",
            {
                commandId: "command-key",
                idempotencyKey: "command-key",
                payload: { command: "printf hello", cwd: "/tmp" },
            },
        ]);
        socket.reply(command, "ok", { commandId: "cmd-1", exitCode: 0, stdout: "hello" });

        await expect(resultPromise).resolves.toEqual({
            commandId: "cmd-1",
            exitCode: 0,
            stdout: "hello",
        });
        expect(httpPaths).toEqual([]);
        client.close();
    });

    it("returns queued responses, generates keys, and correlates concurrent replies", async () => {
        const fake = fakeSocketFactory();
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "u1",
            webSocketFactory: fake.factory,
        });
        const commands = sandbox(client, "s1").commands;
        const first = commands.run({ command: "first", background: true });
        const socket = fake.sockets[0]!;
        socket.open();
        socket.reply(await sentAt(socket, 0), "ok", {});
        await sentAt(socket, 1);

        const second = commands.run({ command: "second" }, { idempotencyKey: "second-key" });
        const firstFrame = await sentAt(socket, 1);
        const secondFrame = await sentAt(socket, 2);
        expect(firstFrame[4]).toMatchObject({ payload: { command: "first", background: true } });
        expect((firstFrame[4] as { idempotencyKey: string }).idempotencyKey).toEqual(
            expect.any(String),
        );
        expect((firstFrame[4] as { idempotencyKey: string }).idempotencyKey).not.toBe("");
        expect(socket.sent.filter((message) => message[3] === "phx_join")).toHaveLength(1);

        socket.reply(secondFrame, "ok", { commandId: "cmd-2", exitCode: 0 });
        socket.reply(firstFrame, "ok", { commandId: "cmd-1", queued: true, pid: 42 });
        await expect(second).resolves.toEqual({ commandId: "cmd-2", exitCode: 0 });
        await expect(first).resolves.toEqual({ commandId: "cmd-1", queued: true, pid: 42 });

        const otherSandbox = sandbox(client, "s2").commands.run(
            { command: "third" },
            { idempotencyKey: "third-key" },
        );
        const secondJoin = await sentAt(socket, 3);
        expect(secondJoin).toEqual(["4", "4", "sandbox:s2:u1", "phx_join", {}]);
        expect(fake.sockets).toHaveLength(1);
        socket.reply(secondJoin, "ok", {});
        const thirdFrame = await sentAt(socket, 4);
        socket.reply(thirdFrame, "ok", { commandId: "cmd-3", exitCode: 0 });
        await expect(otherSandbox).resolves.toEqual({ commandId: "cmd-3", exitCode: 0 });
        client.close();
    });

    it("awaits a correlated queued command completion event", async () => {
        const fake = fakeSocketFactory();
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "u1",
            webSocketFactory: fake.factory,
        });
        const completed = sandbox(client, "s1").commands.run(
            { command: "queued" },
            { idempotencyKey: "queued-key", awaitCompletion: true },
        );
        const socket = fake.sockets[0]!;
        socket.open();
        socket.reply(await sentAt(socket, 0), "ok", {});
        const command = await sentAt(socket, 1);
        socket.reply(command, "ok", { commandId: "queued-key", queued: true });
        socket.broadcast("sandbox:s1:u1", "command_result", {
            commandId: "other-key",
            status: "done",
            result: { exitCode: 1 },
        });
        socket.broadcast("sandbox:s1:u1", "command_result", {
            commandId: "queued-key",
            status: "done",
            result: { exitCode: 0, stdout: "done" },
        });

        await expect(completed).resolves.toEqual({
            commandId: "queued-key",
            queued: true,
            exitCode: 0,
            stdout: "done",
        });
        client.close();
    });

    it("rejects channel errors and pending commands when closed", async () => {
        const fake = fakeSocketFactory();
        const client = new FiremigClient({
            baseUrl: "http://control",
            userId: "u1",
            webSocketFactory: fake.factory,
        });
        const commands = sandbox(client, "s1").commands;
        const failed = commands.run({ command: "fail" }, { idempotencyKey: "fail-key" });
        const socket = fake.sockets[0]!;
        socket.open();
        socket.reply(await sentAt(socket, 0), "ok", {});
        const failedFrame = await sentAt(socket, 1);
        socket.reply(failedFrame, "error", {
            error: { code: ErrorCode.Fenced, message: "stale epoch", retryable: false },
        });
        await expect(failed).rejects.toBeInstanceOf(FencedError);

        const pending = commands.run({ command: "wait" }, { idempotencyKey: "wait-key" });
        await sentAt(socket, 2);
        client.close();
        await expect(pending).rejects.toThrow("client closed");
    });
});
