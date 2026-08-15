import { ErrorCode, FiremigError } from "@firemig/common";
import {
    type BootConfiguration,
    bootSourcePayload,
    type LoadSnapshotRequest,
    loadSnapshotPayload,
    machineConfigPayload,
    networkInterfacePayload,
    rootfsDrivePayload,
} from "./firecracker-payloads.js";
import { nodeUnixHttpTransport, type UnixHttpTransport } from "./unix-http.js";

export type { BootConfiguration, LoadSnapshotRequest } from "./firecracker-payloads.js";
export type {
    UnixHttpRequest,
    UnixHttpResponse,
    UnixHttpTransport,
} from "./unix-http.js";
export { nodeUnixHttpTransport } from "./unix-http.js";

export class FirecrackerClient {
    constructor(
        readonly socketPath: string,
        private readonly transport: UnixHttpTransport = nodeUnixHttpTransport,
        private readonly timeoutMs = 10_000,
    ) {}

    async configure(config: BootConfiguration): Promise<void> {
        await this.put("/boot-source", bootSourcePayload(config));
        await this.put("/drives/rootfs", rootfsDrivePayload(config));
        await this.put("/network-interfaces/eth0", networkInterfacePayload(config));
        await this.put("/vsock", { guest_cid: 3, uds_path: config.vsockPath });
        await this.put("/machine-config", machineConfigPayload(config));
    }

    start(): Promise<void> {
        return this.put("/actions", { action_type: "InstanceStart" });
    }

    pause(): Promise<void> {
        return this.patch("/vm", { state: "Paused" });
    }

    resume(): Promise<void> {
        return this.patch("/vm", { state: "Resumed" });
    }

    createSnapshot(snapshotPath: string, memoryPath: string): Promise<void> {
        return this.put("/snapshot/create", {
            snapshot_type: "Full",
            snapshot_path: snapshotPath,
            mem_file_path: memoryPath,
        });
    }

    loadSnapshot(request: LoadSnapshotRequest): Promise<void> {
        return this.put("/snapshot/load", loadSnapshotPayload(request));
    }

    private put(path: string, body: unknown): Promise<void> {
        return this.request("PUT", path, body);
    }

    private patch(path: string, body: unknown): Promise<void> {
        return this.request("PATCH", path, body);
    }

    private async request(method: "PUT" | "PATCH", path: string, body: unknown): Promise<void> {
        const encoded = JSON.stringify(body);
        const response = await this.transport({
            socketPath: this.socketPath,
            method,
            path,
            headers: {
                "content-type": "application/json",
                "content-length": String(Buffer.byteLength(encoded)),
                accept: "application/json",
            },
            body: encoded,
            timeoutMs: this.timeoutMs,
        });
        if (response.statusCode >= 200 && response.statusCode < 300) return;
        throw new FiremigError(
            {
                code: ErrorCode.FirecrackerApi,
                message: `Firecracker ${method} ${path} returned ${response.statusCode}`,
                retryable: response.statusCode >= 500,
                details: { response: decodeErrorBody(response.body) },
            },
            response.statusCode,
        );
    }
}

function decodeErrorBody(body: string): unknown {
    try {
        return JSON.parse(body) as unknown;
    } catch {
        return body; // Firecracker may return text.
    }
}
