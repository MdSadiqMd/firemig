import type { CompatibilityManifest, SandboxInfo } from "@firemig/common";
import type { FileSystemAdapter, ProcessAdapter } from "../../platform/adapters.js";
import type { UnixHttpTransport } from "../../runtime/firecracker.js";
import type { RelayFactory } from "../../runtime/relay.js";
import type { ArtifactHttpClient } from "../../artifacts/transfer.js";
import type { VsockConnector } from "../../runtime/vsock.js";
import { WorkerCore } from "../core/worker-core.js";
import { prepareMigration } from "./worker-migration.js";
import {
    pauseMigration,
    precopyMigration,
    probeMigration,
    resumeMigration,
    snapshotMigration,
} from "../lifecycle/worker-phases.js";
import { transferMigration } from "./worker-transfer.js";
import type {
    CreateWorkerSandboxRequest,
    PrepareMigrationRequest,
    SnapshotRequest,
    TransferMigrationRequest,
    WorkerConfiguration,
} from "../core/worker-types.js";
import { fenceAndCleanup, rollbackMigration, verifyMigration } from "./worker-verify.js";

/**
 * The coordinator-facing half of the worker API: one method per migration phase.
 * {@link WorkerService} adds the sandbox and artifact half.
 */
export abstract class MigrationFacade {
    protected readonly core: WorkerCore;

    constructor(
        configuration: WorkerConfiguration,
        fs: FileSystemAdapter,
        processAdapter: ProcessAdapter,
        firecrackerTransport?: UnixHttpTransport,
        vsockConnector?: VsockConnector,
        relayFactory?: RelayFactory,
        artifactHttp?: ArtifactHttpClient,
    ) {
        this.core = new WorkerCore(
            configuration,
            fs,
            processAdapter,
            firecrackerTransport,
            vsockConnector,
            relayFactory,
            artifactHttp,
        );
        // Route destination creation back through the subclass so `create` stays the
        // single overridable entry point for making a sandbox.
        this.core.createSandbox = (request) => this.create(request);
    }

    abstract create(request: CreateWorkerSandboxRequest): Promise<SandboxInfo>;

    initialize(): Promise<void> {
        return this.core.epochs.load();
    }

    prepareMigration(
        id: string,
        epoch: number,
        request: PrepareMigrationRequest,
    ): Promise<Record<string, unknown>> {
        return prepareMigration(this.core, id, epoch, request);
    }

    probeMigration(id: string, epoch: number): Promise<Record<string, unknown>> {
        return probeMigration(this.core, id, epoch);
    }

    precopyMigration(id: string, epoch: number): Promise<Record<string, unknown>> {
        return precopyMigration(this.core, id, epoch);
    }

    pauseMigration(id: string, epoch: number): Promise<void> {
        return pauseMigration(this.core, id, epoch);
    }

    snapshotMigration(
        id: string,
        request: SnapshotRequest,
    ): Promise<{ manifest: CompatibilityManifest; bytesTotal: number }> {
        return snapshotMigration(this.core, id, request);
    }

    transferMigration(
        id: string,
        epoch: number,
        request: TransferMigrationRequest,
    ): Promise<{ bytesTotal: number; bytesTransferred: number }> {
        return transferMigration(this.core, id, epoch, request);
    }

    resumeMigration(id: string, epoch: number): Promise<void> {
        return resumeMigration(this.core, id, epoch);
    }

    verifyMigration(
        id: string,
        epoch: number,
        migrationId: string,
    ): Promise<Record<string, unknown>> {
        return verifyMigration(this.core, id, epoch, migrationId);
    }

    rollbackMigration(id: string, epoch: number, repairClock: boolean): Promise<void> {
        return rollbackMigration(this.core, id, epoch, repairClock);
    }

    fenceAndCleanup(id: string, epoch: number, migrationId: string): Promise<string> {
        return fenceAndCleanup(this.core, id, epoch, migrationId);
    }
}
