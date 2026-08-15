import { createConnection, createServer, type Server, type Socket } from "node:net";

export interface RelayHandle {
    close(): Promise<void>;
}

export type RelayFactory = (
    listenPort: number,
    targetHost: string,
    targetPort: number,
) => Promise<RelayHandle>;

export const nodeRelayFactory: RelayFactory = (listenPort, targetHost, targetPort) =>
    new Promise((resolve, reject) => {
        const sockets = new Set<Socket>();
        const server = createServer((client) => {
            const upstream = createConnection(targetPort, targetHost);
            sockets.add(client);
            sockets.add(upstream);
            const closeBoth = () => {
                client.destroy();
                upstream.destroy();
                sockets.delete(client);
                sockets.delete(upstream);
            };
            client.once("error", closeBoth);
            upstream.once("error", closeBoth);
            client.once("close", closeBoth);
            upstream.once("close", closeBoth);
            client.pipe(upstream);
            upstream.pipe(client);
        });
        server.once("error", reject);
        server.listen({ host: "0.0.0.0", port: listenPort, exclusive: true }, () => {
            server.off("error", reject);
            server.on("error", () => undefined);
            resolve(new NodeRelayHandle(server, sockets));
        });
    });

class NodeRelayHandle implements RelayHandle {
    constructor(
        private readonly server: Server,
        private readonly sockets: Set<Socket>,
    ) {}

    close(): Promise<void> {
        for (const socket of this.sockets) socket.destroy();
        this.sockets.clear();
        return new Promise((resolve, reject) => {
            this.server.close((error) => (error === undefined ? resolve() : reject(error)));
        });
    }
}

export class RelayLifecycle {
    private readonly relays = new Map<string, Map<number, RelayHandle>>();

    constructor(private readonly factory: RelayFactory = nodeRelayFactory) {}

    async start(
        sandboxId: string,
        guestPort: number,
        hostPort: number,
        targetHost: string,
    ): Promise<void> {
        const sandboxRelays = this.relays.get(sandboxId) ?? new Map<number, RelayHandle>();
        if (sandboxRelays.has(guestPort)) return;
        const relay = await this.factory(hostPort, targetHost, guestPort);
        sandboxRelays.set(guestPort, relay);
        this.relays.set(sandboxId, sandboxRelays);
    }

    async stopSandbox(sandboxId: string): Promise<void> {
        const sandboxRelays = this.relays.get(sandboxId);
        if (sandboxRelays === undefined) return;
        await Promise.allSettled([...sandboxRelays.values()].map((relay) => relay.close()));
        this.relays.delete(sandboxId);
    }
}
