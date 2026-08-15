import { ErrorCode, FiremigError } from "@firemig/common";
import {
    deriveNetworkIdentity,
    deterministicHostPort,
    type NetworkIdentity,
} from "../../runtime/network.js";
import type { CreateWorkerSandboxRequest, WorkerConfiguration } from "./worker-types.js";

const MAX_INTERFACE_NAME = 15;
const DEFAULT_PORT_BASE = 20_000;

/** Owns the netns / veth / subnet / relay-port namespaces so two sandboxes never collide. */
export class ResourceAllocator {
    private readonly networkOwners = new Map<string, string>();
    private readonly portOwners = new Map<number, string>();

    constructor(private readonly configuration: WorkerConfiguration) {}

    allocateNetwork(
        request: CreateWorkerSandboxRequest,
    ): NetworkIdentity & { keys: readonly string[] } {
        const pinned =
            request.netns !== undefined ||
            request.hostVeth !== undefined ||
            request.hostAddress !== undefined ||
            request.namespaceAddress !== undefined;

        for (let attempt = 0; attempt < 1_024; attempt += 1) {
            const network = this.deriveNetwork(request, attempt);
            if (
                network.netns.length > MAX_INTERFACE_NAME ||
                network.hostVeth.length > MAX_INTERFACE_NAME
            )
                throw new Error(
                    "Network namespace and host veth names must be at most 15 characters",
                );
            const keys = networkKeys(network);
            const collision = keys.some((key) => {
                const owner = this.networkOwners.get(key);
                return owner !== undefined && owner !== request.id;
            });
            if (collision && !pinned) continue;
            if (collision)
                throw new FiremigError(
                    {
                        code: ErrorCode.NoCapacity,
                        message: "Requested network allocation collides with another sandbox",
                        retryable: true,
                    },
                    409,
                );
            for (const key of keys) this.networkOwners.set(key, request.id);
            return { ...network, keys };
        }
        throw new FiremigError(
            {
                code: ErrorCode.NoCapacity,
                message: "Unable to allocate a collision-free sandbox network",
                retryable: true,
            },
            503,
        );
    }

    releaseNetwork(id: string, keys: readonly string[]): void {
        for (const key of keys)
            if (this.networkOwners.get(key) === id) this.networkOwners.delete(key);
    }

    allocatePort(id: string, guestPort: number): number {
        const portBase = this.configuration.portBase ?? DEFAULT_PORT_BASE;
        const preferred = deterministicHostPort(
            portBase,
            this.configuration.workerId,
            id,
            guestPort,
        );
        const owner = `${id}:${guestPort}`;
        const available = 65_536 - portBase;
        for (let offset = 0; offset < available; offset += 1) {
            const port = portBase + ((preferred - portBase + offset) % available);
            const existing = this.portOwners.get(port);
            if (existing === undefined || existing === owner) {
                this.portOwners.set(port, owner);
                return port;
            }
        }
        throw new FiremigError(
            {
                code: ErrorCode.NoCapacity,
                message: "No worker relay ports are available",
                retryable: true,
            },
            503,
        );
    }

    releasePort(port: number): void {
        this.portOwners.delete(port);
    }

    releasePorts(id: string): void {
        for (const [port, owner] of this.portOwners)
            if (owner.startsWith(`${id}:`)) this.portOwners.delete(port);
    }

    private deriveNetwork(request: CreateWorkerSandboxRequest, attempt: number): NetworkIdentity {
        const derived = deriveNetworkIdentity(this.configuration.workerId, request.id, attempt);
        return {
            ...derived,
            ...(request.netns === undefined ? {} : { netns: request.netns }),
            ...(request.hostVeth === undefined ? {} : { hostVeth: request.hostVeth }),
            ...(request.hostAddress === undefined ? {} : { hostAddress: request.hostAddress }),
            ...(request.namespaceAddress === undefined
                ? {}
                : { namespaceAddress: request.namespaceAddress }),
        };
    }
}

function networkKeys(network: NetworkIdentity): string[] {
    return [
        `netns:${network.netns}`,
        `veth:${network.hostVeth}`,
        `subnet:${network.hostAddress.split("/")[0]}:${network.namespaceAddress.split("/")[0]}`,
    ];
}
