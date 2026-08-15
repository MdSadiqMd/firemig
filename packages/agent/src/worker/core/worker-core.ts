import type { CompatibilityManifest, SandboxInfo } from "@firemig/common";
import { SandboxState } from "@firemig/common";
import type { FileSystemAdapter, ProcessAdapter } from "../../platform/adapters.js";
import { EpochStore } from "../../platform/epochs.js";
import type { UnixHttpTransport } from "../../runtime/firecracker.js";
import { PathModel } from "../../platform/paths.js";
import { networkDeletePlan } from "../../planning/planner.js";
import { ProcessLifecycle } from "../../platform/processes.js";
import { RelayLifecycle, type RelayFactory } from "../../runtime/relay.js";
import type { ArtifactHttpClient } from "../../artifacts/transfer.js";
import type { VsockConnector } from "../../runtime/vsock.js";
import { ResourceAllocator } from "./worker-allocator.js";
import { createSandbox } from "../lifecycle/worker-create.js";
import { fencedError, sandboxNotFound, stateMismatch } from "./worker-errors.js";
import type {
    CreateWorkerSandboxRequest,
    MigrationReservation,
    SandboxRecord,
    WorkerConfiguration,
} from "./worker-types.js";

/**
 * Shared state and the two record accessors every worker operation goes through.
 * `mutableRecord` is the single choke point that enforces the fencing epoch.
 */
export class WorkerCore {
    readonly paths: PathModel;
    readonly lifecycle: ProcessLifecycle;
    readonly relays: RelayLifecycle;
    readonly epochs: EpochStore;
    readonly allocator: ResourceAllocator;
    readonly sandboxes = new Map<string, SandboxRecord>();
    readonly consumedSnapshots = new Set<string>();
    readonly migrations = new Map<string, MigrationReservation>();
    readonly manifests = new Map<string, CompatibilityManifest>();

    /**
     * Seam for creating the destination sandbox. WorkerService reassigns this to its own
     * `create` method so callers (and tests) can override sandbox creation in one place.
     */
    createSandbox: (request: CreateWorkerSandboxRequest) => Promise<SandboxInfo> = (request) =>
        createSandbox(this, request);

    constructor(
        readonly configuration: WorkerConfiguration,
        readonly fs: FileSystemAdapter,
        processAdapter: ProcessAdapter,
        readonly firecrackerTransport?: UnixHttpTransport,
        readonly vsockConnector?: VsockConnector,
        relayFactory?: RelayFactory,
        readonly artifactHttp?: ArtifactHttpClient,
    ) {
        this.paths = new PathModel(configuration.workerRoot, configuration.canonicalRoot);
        this.lifecycle = new ProcessLifecycle(processAdapter);
        this.relays = new RelayLifecycle(relayFactory);
        this.epochs = new EpochStore(`${configuration.workerRoot}/epochs.json`, fs);
        this.allocator = new ResourceAllocator(configuration);
        if (
            configuration.portBase !== undefined &&
            (!Number.isInteger(configuration.portBase) ||
                configuration.portBase < 1 ||
                configuration.portBase > 65_535)
        ) {
            throw new Error("portBase must be between 1 and 65535");
        }
    }

    record(id: string): SandboxRecord {
        const record = this.sandboxes.get(id);
        if (record === undefined) throw sandboxNotFound(id);
        return record;
    }

    async mutableRecord(
        id: string,
        epoch: number,
        expected?: SandboxState,
    ): Promise<SandboxRecord> {
        const record = this.record(id);
        const accepted = await this.epochs.accept(id, epoch);
        if (accepted.advanced && record.info.state !== SandboxState.Booting) {
            await this.fenceQuietly(record, id, epoch);
            throw fencedError(id, epoch, epoch);
        }
        if (record.info.state === SandboxState.Fenced || epoch < record.info.epoch)
            throw fencedError(id, epoch, record.info.epoch);
        if (expected !== undefined && record.info.state !== expected)
            throw stateMismatch(expected, record.info.state);
        return record;
    }

    /** Best-effort teardown used when a newer epoch supersedes the owner mid-request. */
    private async fenceQuietly(record: SandboxRecord, id: string, epoch: number): Promise<void> {
        const wasRunning = record.info.state === SandboxState.Running;
        record.info = { ...record.info, state: SandboxState.Fenced, epoch };
        await this.relays.stopSandbox(id);
        const actions: Promise<unknown>[] = [this.downHostVeth(record)];
        if (wasRunning) actions.push(record.firecracker.pause());
        await Promise.allSettled(actions);
    }

    downHostVeth(record: SandboxRecord): Promise<void> {
        return this.lifecycle.runPlans([
            { file: "ip", args: ["link", "set", record.hostVeth, "down"] },
        ]);
    }

    async runCleanupPlans(netns: string, hostVeth: string): Promise<void> {
        for (const plan of networkDeletePlan(netns, hostVeth)) {
            try {
                await this.lifecycle.runPlans([plan]);
            } catch {
                /* Cleanup is best effort and idempotent. */
            }
        }
    }
}
