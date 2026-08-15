import { writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SandboxState, type CompatibilityManifest, type SandboxInfo } from "@firemig/common";
import {
    nodeFileSystem,
    type FileSystemAdapter,
    type ProcessAdapter,
    type SpawnedProcess,
} from "../src/platform/adapters.js";
import { parsePeerUrls, parsePortBase } from "../src/platform/config.js";
import { deriveNetworkIdentity, deterministicHostPort } from "../src/runtime/network.js";
import { networkCreatePlan } from "../src/planning/planner.js";
import {
    WorkerService,
    type PrepareMigrationRequest,
    type WorkerConfiguration,
} from "../src/worker/index.js";
import type { ArtifactHttpClient } from "../src/artifacts/transfer.js";

const temporaryDirectories: string[] = [];
afterEach(async () =>
    Promise.all(
        temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })),
    ),
);

const configuration: WorkerConfiguration = {
    workerId: "worker-b",
    region: "worker-b",
    workerRoot: "/worker-b",
    firecrackerBinary: "/firecracker",
    kernelPath: "/vmlinux",
    baseRootfsPath: "/rootfs",
    proxyHost: "192.0.2.20",
    portBase: 30_000,
    hostCompatibility: {
        firecrackerVersion: "1",
        firecrackerDigest: "fc",
        snapshotFormatVersion: "3",
        hostKernelVersion: "6.1",
        architecture: "x64",
        cpuVendor: "GenuineIntel",
        cpuModel: "1",
        cpuFamily: "6",
        cpuStepping: "1",
        guestKernelDigest: "kernel",
        cpuTemplate: "T2S",
        smt: false,
        hugePages: "None",
    },
};

describe("deterministic worker networking", () => {
    it("derives stable, worker-specific Linux names and collision-resistant /30 networks", () => {
        const first = deriveNetworkIdentity("worker-a", "sandbox-1");
        expect(deriveNetworkIdentity("worker-a", "sandbox-1")).toEqual(first);
        expect(deriveNetworkIdentity("worker-b", "sandbox-1")).not.toEqual(first);
        expect(first.netns.length).toBeLessThanOrEqual(15);
        expect(first.hostVeth.length).toBeLessThanOrEqual(15);
        expect(first.hostAddress).toMatch(/^10\.\d+\.\d+\.\d+\/30$/);
        const subnets = new Set(
            Array.from(
                { length: 100 },
                (_, index) => deriveNetworkIdentity("worker-a", `sandbox-${index}`).subnet,
            ),
        );
        expect(subnets.size).toBe(100);
        const plans = networkCreatePlan({ sandboxId: "sandbox-1", ...first });
        expect(
            plans.some(
                (plan) => plan.args.includes("172.16.0.1/30") && plan.args.includes("fmtap0"),
            ),
        ).toBe(true);
    });

    it("assigns a stable worker host port at or above FIREMIG_PORT_BASE", () => {
        const port = deterministicHostPort(30_000, "worker-a", "sandbox-1", 8080);
        expect(deterministicHostPort(30_000, "worker-a", "sandbox-1", 8080)).toBe(port);
        expect(port).toBeGreaterThanOrEqual(30_000);
        expect(port).toBeLessThanOrEqual(65_535);
        expect(deterministicHostPort(30_000, "worker-b", "sandbox-1", 8080)).not.toBe(port);
    });

    it("creates with omitted network fields and returns the worker relay endpoint", async () => {
        const workerRoot = await mkdtemp(join(tmpdir(), "firemig-network-"));
        temporaryDirectories.push(workerRoot);
        let pid = 100;
        const plans: Array<{ file: string; args: readonly string[] }> = [];
        const spawned = (): SpawnedProcess => ({
            pid: (pid += 1),
            exited: new Promise(() => undefined),
            kill: () => true,
        });
        const processes: ProcessAdapter = {
            spawn(file, args) {
                const socketFlag = args.indexOf("--api-sock");
                if (socketFlag >= 0) writeFileSync(args[socketFlag + 1]!, "");
                return spawned();
            },
            run: vi.fn(async (file, args) => {
                plans.push({ file, args });
                return { stdout: "", stderr: "" };
            }),
        };
        const relays: Array<{ listenPort: number; targetHost: string; targetPort: number }> = [];
        const worker = new WorkerService(
            { ...configuration, workerRoot },
            nodeFileSystem,
            processes,
            undefined,
            undefined,
            async (listenPort, targetHost, targetPort) => {
                relays.push({ listenPort, targetHost, targetPort });
                return { close: async () => undefined };
            },
        );
        await worker.initialize();
        await worker.create({ id: "sandbox-1", epoch: 5, cpu: 2, memoryMb: 1024, mode: "restore" });
        const exposure = await worker.exposePort("sandbox-1", 5, 8080);
        const expectedPort = deterministicHostPort(30_000, "worker-b", "sandbox-1", 8080);
        expect(exposure).toEqual({
            guestPort: 8080,
            proxyHost: "192.0.2.20",
            proxyPort: expectedPort,
            url: `tcp://192.0.2.20:${expectedPort}`,
        });
        expect(relays).toEqual([
            {
                listenPort: expectedPort,
                targetHost: expect.stringMatching(/^10\./),
                targetPort: 8080,
            },
        ]);
        expect(plans.flatMap((plan) => plan.args).some((argument) => argument === "fmv0")).toBe(
            true,
        );
        expect(plans.every((plan) => plan.file !== "sh" && plan.file !== "bash")).toBe(true);
    });

    it("parses peer URLs and port base configuration", () => {
        expect(
            parsePeerUrls("worker-a=http://127.0.0.1:4101/,worker-b=https://worker-b:4102"),
        ).toEqual({
            "worker-a": "http://127.0.0.1:4101",
            "worker-b": "https://worker-b:4102",
        });
        expect(parsePortBase("31000")).toBe(31_000);
        expect(() => parsePeerUrls("worker-a=ftp://host")).toThrow("HTTP or HTTPS");
    });
});

describe("migration prepare", () => {
    it("creates one restore-mode destination reservation and replays prestage idempotently", async () => {
        const worker = new WorkerService(
            configuration,
            {} as FileSystemAdapter,
            {} as ProcessAdapter,
        );
        const info: SandboxInfo = {
            id: "sandbox-1",
            region: "worker-b",
            worker: "worker-b",
            state: SandboxState.Booting,
            epoch: 5,
            cpu: 2,
            memoryMb: 1024,
            createdAt: "now",
        };
        const create = vi.spyOn(worker, "create").mockResolvedValue(info);
        const request: PrepareMigrationRequest = {
            migrationId: "move-1",
            stage: "prestage",
            source: "worker-a",
            destination: "worker-b",
            sandbox: { id: "sandbox-1", cpu: 2, memoryMb: 1024, bootId: "boot-1" },
        };
        const first = await worker.prepareMigration("sandbox-1", 5, request);
        const replay = await worker.prepareMigration("sandbox-1", 5, request);
        expect(first).toMatchObject({ reserved: true, prestaged: true });
        expect(replay).toMatchObject({ reserved: true, prestaged: true });
        expect(create).toHaveBeenCalledTimes(1);
        expect(create).toHaveBeenCalledWith(
            expect.objectContaining({ id: "sandbox-1", epoch: 5, mode: "restore" }),
        );
    });

    it("pulls state, memory, and disk from the configured peer with auth", async () => {
        const workerRoot = await mkdtemp(join(tmpdir(), "firemig-peer-"));
        temporaryDirectories.push(workerRoot);
        let pid = 200;
        const processes: ProcessAdapter = {
            spawn(_file, args) {
                const socketFlag = args.indexOf("--api-sock");
                if (socketFlag >= 0) writeFileSync(args[socketFlag + 1]!, "");
                return { pid: (pid += 1), exited: new Promise(() => undefined), kill: () => true };
            },
            run: async () => ({ stdout: "", stderr: "" }),
        };
        const contents = {
            state: Buffer.from("state"),
            mem: Buffer.from("memory"),
            disk: Buffer.from("disk"),
        };
        const calls: Array<{ url: string; authorization: string | null }> = [];
        const http: ArtifactHttpClient = async (url, init) => {
            const kind = url.split("/").at(-1) as keyof typeof contents;
            calls.push({ url, authorization: new Headers(init.headers).get("authorization") });
            return {
                status: 200,
                headers: new Headers(),
                body: (async function* () {
                    yield contents[kind];
                })(),
            };
        };
        const descriptor = (kind: keyof typeof contents) => ({
            kind,
            name: kind,
            size: contents[kind].length,
            sha256: createHash("sha256").update(contents[kind]).digest("hex"),
        });
        const manifest: CompatibilityManifest = {
            migrationId: "move-1",
            sandboxId: "sandbox-1",
            sourceEpoch: 4,
            firecrackerVersion: "1",
            firecrackerDigest: "fc",
            snapshotFormatVersion: "3",
            hostKernelVersion: "6.1",
            cpu: {
                architecture: "x64",
                vendor: "GenuineIntel",
                model: "1",
                family: "6",
                stepping: "1",
            },
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
                state: descriptor("state"),
                mem: descriptor("mem"),
                disk: descriptor("disk"),
            },
            consumed: false,
        };
        const worker = new WorkerService(
            {
                ...configuration,
                workerRoot,
                peerUrls: { "worker-a": "http://worker-a:4101" },
                peerAuthToken: "secret",
            },
            nodeFileSystem,
            processes,
            undefined,
            undefined,
            undefined,
            http,
        );
        await worker.initialize();
        await worker.create({ id: "sandbox-1", epoch: 5, cpu: 2, memoryMb: 1024, mode: "restore" });
        const result = await worker.transferMigration("sandbox-1", 5, {
            migrationId: "move-1",
            source: "worker-a",
            manifest,
        });
        expect(calls.map((call) => call.url).sort()).toEqual(
            [
                "http://worker-a:4101/internal/sandboxes/sandbox-1/artifacts/state",
                "http://worker-a:4101/internal/sandboxes/sandbox-1/artifacts/mem",
                "http://worker-a:4101/internal/sandboxes/sandbox-1/artifacts/disk",
            ].sort(),
        );
        expect(calls.every((call) => call.authorization === "Bearer secret")).toBe(true);
        expect(result.bytesTransferred).toBe(
            contents.state.length + contents.mem.length + contents.disk.length,
        );
    });

    it("uses parallel atomic hard links when workers share a host filesystem", async () => {
        const sharedRoot = await mkdtemp(join(tmpdir(), "firemig-shared-"));
        temporaryDirectories.push(sharedRoot);
        const sandboxId = "sandbox-1";
        const sourceDirectory = join(sharedRoot, "worker-a", "sandboxes", sandboxId);
        const destinationRoot = join(sharedRoot, "worker-b");
        await mkdir(sourceDirectory, { recursive: true });
        const contents = {
            state: Buffer.from("state"),
            mem: Buffer.from("memory"),
            disk: Buffer.from("disk"),
        };
        await Promise.all(
            Object.entries(contents).map(([name, content]) =>
                writeFile(join(sourceDirectory, name), content),
            ),
        );
        let pid = 300;
        const processes: ProcessAdapter = {
            spawn(_file, args) {
                const socketFlag = args.indexOf("--api-sock");
                if (socketFlag >= 0) writeFileSync(args[socketFlag + 1]!, "");
                return { pid: (pid += 1), exited: new Promise(() => undefined), kill: () => true };
            },
            async run(file, args) {
                if (file === "cp") await copyFile(args.at(-2)!, args.at(-1)!);
                return { stdout: "", stderr: "" };
            },
        };
        const links: Array<[string, string]> = [];
        const fs: FileSystemAdapter = {
            ...nodeFileSystem,
            async link(existingPath, newPath) {
                links.push([existingPath, newPath]);
                await nodeFileSystem.link(existingPath, newPath);
            },
        };
        const descriptor = (kind: keyof typeof contents) => ({
            kind,
            name: kind,
            size: contents[kind].length,
            sha256: createHash("sha256").update(contents[kind]).digest("hex"),
        });
        const manifest: CompatibilityManifest = {
            migrationId: "move-1",
            sandboxId,
            sourceEpoch: 4,
            firecrackerVersion: "1",
            firecrackerDigest: "fc",
            snapshotFormatVersion: "3",
            hostKernelVersion: "6.1",
            cpu: {
                architecture: "x64",
                vendor: "GenuineIntel",
                model: "1",
                family: "6",
                stepping: "1",
            },
            guestKernelDigest: "kernel",
            cpuTemplate: "T2S",
            vcpuCount: 2,
            memSizeMib: 1024,
            smt: false,
            hugePages: "None",
            driveCanonicalPath: `/var/lib/firemig/sandboxes/${sandboxId}/rootfs.ext4`,
            tapName: "fmtap0",
            vsockCanonicalPath: `/var/lib/firemig/sandboxes/${sandboxId}/vsock.socket`,
            artifacts: {
                state: descriptor("state"),
                mem: descriptor("mem"),
                disk: descriptor("disk"),
            },
            consumed: false,
        };
        const worker = new WorkerService(
            {
                ...configuration,
                workerRoot: destinationRoot,
                sharedWorkerRoot: sharedRoot,
                peerUrls: { "worker-a": "http://127.0.0.1:4101" },
            },
            fs,
            processes,
            undefined,
            undefined,
            undefined,
            async () => {
                throw new Error("HTTP transfer must not run for shared workers");
            },
        );
        await worker.initialize();
        await worker.create({ id: sandboxId, epoch: 5, cpu: 2, memoryMb: 1024, mode: "restore" });
        await worker.transferMigration(sandboxId, 5, {
            migrationId: "move-1",
            source: "worker-a",
            manifest,
        });
        expect(links).toHaveLength(3);
        await expect(readFile(worker.destinationArtifactPath(sandboxId, "state"))).resolves.toEqual(
            contents.state,
        );
        await expect(readFile(worker.destinationArtifactPath(sandboxId, "mem"))).resolves.toEqual(
            contents.mem,
        );
        await expect(readFile(worker.destinationArtifactPath(sandboxId, "disk"))).resolves.toEqual(
            contents.disk,
        );
    });
});
