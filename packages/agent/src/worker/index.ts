import type {
    ArtifactDescriptor,
    ArtifactKind,
    CommandResult,
    CompatibilityManifest,
    PortExposure,
    RunCommandRequest,
    SandboxInfo,
    WriteFileRequest,
    WriteFileResult,
} from "@firemig/common";
import { artifactPath, readArtifact } from "./snapshot/worker-artifact-paths.js";
import { createSandbox } from "./lifecycle/worker-create.js";
import { MigrationFacade } from "./migration/worker-facade.js";
import { exposeGuestPort, runGuestCommand, writeGuestFile } from "./lifecycle/worker-guest-ops.js";
import {
    fenceSandbox,
    loadSnapshot,
    pauseSandbox,
    quarantineSandbox,
    resumeSandbox,
} from "./lifecycle/worker-lifecycle.js";
import { validateManifest } from "./snapshot/worker-manifest.js";
import { createSnapshot } from "./snapshot/worker-snapshot.js";
import type { CreateWorkerSandboxRequest, SnapshotRequest } from "./core/worker-types.js";

export type {
    CreateWorkerSandboxRequest,
    PrepareMigrationRequest,
    SnapshotRequest,
    TransferMigrationRequest,
    WorkerConfiguration,
} from "./core/worker-types.js";

/** HTTP-facing boundary for one worker. All state lives in the shared `WorkerCore`. */
export class WorkerService extends MigrationFacade {
    create(request: CreateWorkerSandboxRequest): Promise<SandboxInfo> {
        return createSandbox(this.core, request);
    }

    get(id: string): SandboxInfo {
        return { ...this.core.record(id).info };
    }

    command(id: string, epoch: number, request: RunCommandRequest): Promise<CommandResult> {
        return runGuestCommand(this.core, id, epoch, request);
    }

    writeFile(id: string, epoch: number, request: WriteFileRequest): Promise<WriteFileResult> {
        return writeGuestFile(this.core, id, epoch, request);
    }

    exposePort(id: string, epoch: number, guestPort: number): Promise<PortExposure> {
        return exposeGuestPort(this.core, id, epoch, guestPort);
    }

    pause(id: string, epoch: number): Promise<void> {
        return pauseSandbox(this.core, id, epoch);
    }

    snapshot(id: string, request: SnapshotRequest): Promise<CompatibilityManifest> {
        return createSnapshot(this.core, id, request);
    }

    load(id: string, epoch: number, manifest: CompatibilityManifest): Promise<void> {
        return loadSnapshot(this.core, id, epoch, manifest);
    }

    resume(id: string, epoch: number): Promise<void> {
        return resumeSandbox(this.core, id, epoch);
    }

    fence(id: string, epoch: number): Promise<void> {
        return fenceSandbox(this.core, id, epoch);
    }

    quarantine(id: string, epoch: number, migrationId: string): Promise<string> {
        return quarantineSandbox(this.core, id, epoch, migrationId);
    }

    artifact(id: string, kind: ArtifactKind): { path: string; descriptor: ArtifactDescriptor } {
        return readArtifact(this.core, id, kind);
    }

    destinationArtifactPath(id: string, kind: ArtifactKind): string {
        return artifactPath(this.core.record(id), kind);
    }

    registerArtifact(id: string, descriptor: ArtifactDescriptor): void {
        this.core.record(id).artifacts[descriptor.kind] = descriptor;
    }

    validateManifest(manifest: CompatibilityManifest): void {
        validateManifest(this.core, manifest);
    }
}
