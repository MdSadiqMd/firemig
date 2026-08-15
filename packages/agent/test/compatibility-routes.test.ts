import { afterEach, describe, expect, it, vi } from "vitest";
import { MigrationPhase, SandboxState, type CompatibilityManifest } from "@firemig/common";
import { buildAgentServer } from "../src/server/server.js";
import type { FileSystemAdapter } from "../src/platform/adapters.js";
import type { WorkerService } from "../src/worker/index.js";

const manifest: CompatibilityManifest = {
    migrationId: "move-1",
    sandboxId: "sandbox-1",
    sourceEpoch: 4,
    firecrackerVersion: "1.10.0",
    firecrackerDigest: "fc",
    snapshotFormatVersion: "3",
    hostKernelVersion: "6.1",
    cpu: { architecture: "x64", vendor: "GenuineIntel", model: "1", family: "6", stepping: "1" },
    guestKernelDigest: "kernel",
    cpuTemplate: "T2S",
    vcpuCount: 2,
    memSizeMib: 1024,
    smt: false,
    hugePages: "None",
    driveCanonicalPath: "/var/lib/firemig/sandboxes/sandbox-1/rootfs.ext4",
    tapName: "fmtap0",
    vsockCanonicalPath: "/var/lib/firemig/sandboxes/sandbox-1/vsock.socket",
    artifacts: {
        state: { kind: "state", name: "state", size: 1, sha256: "a" },
        mem: { kind: "mem", name: "mem", size: 2, sha256: "b" },
        disk: { kind: "disk", name: "disk", size: 3, sha256: "c" },
    },
    consumed: false,
};

const servers: Array<ReturnType<typeof buildAgentServer>> = [];
afterEach(async () => Promise.all(servers.splice(0).map((server) => server.close())));

function setup() {
    const worker = {
        prepareMigration: vi.fn(async () => ({ reserved: true })),
        probeMigration: vi.fn(async () => ({ path: "SAFE" })),
        precopyMigration: vi.fn(async () => ({ bytesTotal: 0, bytesTransferred: 0 })),
        pauseMigration: vi.fn(async () => undefined),
        snapshotMigration: vi.fn(async () => ({ manifest, bytesTotal: 6 })),
        transferMigration: vi.fn(async () => ({ bytesTotal: 6, bytesTransferred: 6 })),
        load: vi.fn(async () => undefined),
        resumeMigration: vi.fn(async () => undefined),
        verifyMigration: vi.fn(async () => ({ healthy: true, bootId: "boot-1" })),
        rollbackMigration: vi.fn(async () => undefined),
        fenceAndCleanup: vi.fn(async () => "/quarantine/move-1"),
    };
    const server = buildAgentServer({
        worker: worker as unknown as WorkerService,
        fs: {} as FileSystemAdapter,
        logger: false,
    });
    servers.push(server);
    return { worker, server };
}

describe("coordinator compatibility routes", () => {
    it("matches every migration URL and coordinator payload shape", async () => {
        const { worker, server } = setup();
        const headers = { "x-firemig-epoch": "5", "content-type": "application/json" };
        const requests = [
            {
                url: "/internal/sandboxes/sandbox-1/migrations/move-1/prepare",
                payload: {
                    migration_id: "move-1",
                    stage: "reserve",
                    source: "worker-a",
                    destination: "worker-b",
                    sandbox: { id: "sandbox-1", cpu: 2, memoryMb: 1024, bootId: "boot-1" },
                },
            },
            {
                url: "/internal/sandboxes/sandbox-1/migrations/move-1/prepare",
                payload: {
                    migration_id: "move-1",
                    stage: "prestage",
                    source: "worker-a",
                    destination: "worker-b",
                    sandbox: { id: "sandbox-1", cpu: 2, memoryMb: 1024, bootId: "boot-1" },
                },
            },
            { url: "/internal/sandboxes/sandbox-1/migration/probe", payload: {} },
            {
                url: "/internal/sandboxes/sandbox-1/migration/precopy",
                payload: { migrationId: "move-1" },
            },
            { url: "/internal/sandboxes/sandbox-1/migration/pause", payload: {} },
            {
                url: "/internal/sandboxes/sandbox-1/migration/snapshot",
                payload: { migrationId: "move-1" },
            },
            {
                url: "/internal/sandboxes/sandbox-1/migration/transfer",
                payload: { migrationId: "move-1", source: "worker-a", manifest },
            },
            {
                url: "/internal/sandboxes/sandbox-1/migration/load",
                payload: { migrationId: "move-1", manifest, resumeVm: false },
            },
            { url: "/internal/sandboxes/sandbox-1/migration/resume", payload: {} },
            {
                url: "/internal/sandboxes/sandbox-1/migration/verify",
                payload: { migrationId: "move-1" },
            },
            {
                url: "/internal/sandboxes/sandbox-1/migration/rollback",
                payload: { migrationId: "move-1", repairClock: true },
            },
            {
                url: "/internal/sandboxes/sandbox-1/migration/fence-and-cleanup",
                payload: { migrationId: "move-1", destination: "worker-b" },
            },
        ];
        const responses = [];
        for (const request of requests)
            responses.push(
                await server.inject({
                    method: "POST",
                    url: request.url,
                    headers,
                    payload: request.payload,
                }),
            );
        expect(responses.map((response) => response.statusCode)).toEqual(
            Array(requests.length).fill(200),
        );
        expect(responses[5]!.json()).toMatchObject({
            bytesTotal: 6,
            manifest: { migrationId: "move-1" },
        });
        expect(responses[6]!.json()).toEqual({ bytesTotal: 6, bytesTransferred: 6 });
        expect(worker.prepareMigration).toHaveBeenCalledWith(
            "sandbox-1",
            5,
            expect.objectContaining({ migrationId: "move-1", stage: "reserve" }),
        );
        expect(worker.prepareMigration).toHaveBeenCalledWith(
            "sandbox-1",
            5,
            expect.objectContaining({ migrationId: "move-1", stage: "prestage" }),
        );
        expect(worker.load).toHaveBeenCalledWith(
            "sandbox-1",
            5,
            expect.objectContaining({ migrationId: "move-1" }),
        );
        expect(worker.verifyMigration).toHaveBeenCalledWith("sandbox-1", 5, "move-1");
        expect(worker.rollbackMigration).toHaveBeenCalledWith("sandbox-1", 5, true);
        expect(worker.fenceAndCleanup).toHaveBeenCalledWith("sandbox-1", 5, "move-1");
    });
});
