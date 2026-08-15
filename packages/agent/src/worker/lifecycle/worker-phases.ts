import type { CompatibilityManifest } from "@firemig/common";
import { ErrorCode, FiremigError, SandboxState } from "@firemig/common";
import type { WorkerCore } from "../core/worker-core.js";
import { conflict, totalArtifactBytes, workerBadRequest } from "../core/worker-errors.js";
import {
    fenceSandbox,
    pauseSandbox,
    quarantineSandbox,
    resumeSandbox,
} from "./worker-lifecycle.js";
import { createSnapshot } from "../snapshot/worker-snapshot.js";
import type { SnapshotRequest } from "../core/worker-types.js";

export async function probeMigration(
    core: WorkerCore,
    id: string,
    epoch: number,
): Promise<Record<string, unknown>> {
    const record = await core.mutableRecord(id, epoch, SandboxState.Running);
    const ready = await record.guest.ready();
    return {
        path: "SAFE",
        verdict: "SAFE",
        ready: true,
        bootId: ready.bootId,
        serialFullSnapshot: true,
    };
}

export async function precopyMigration(
    core: WorkerCore,
    id: string,
    epoch: number,
): Promise<Record<string, unknown>> {
    await core.mutableRecord(id, epoch, SandboxState.Running);
    return { skipped: true, reason: "serial_full_snapshot", bytesTotal: 0, bytesTransferred: 0 };
}

export async function pauseMigration(core: WorkerCore, id: string, epoch: number): Promise<void> {
    if (core.record(id).info.state === SandboxState.Paused) return;
    await pauseSandbox(core, id, epoch);
}

export async function snapshotMigration(
    core: WorkerCore,
    id: string,
    request: SnapshotRequest,
): Promise<{ manifest: CompatibilityManifest; bytesTotal: number }> {
    const cached = core.manifests.get(request.migrationId);
    if (cached !== undefined) {
        if (cached.sandboxId !== id || cached.sourceEpoch !== request.epoch)
            throw conflict(ErrorCode.IdempotencyKeyConflict, "Snapshot migration id was reused");
        return { manifest: cached, bytesTotal: totalArtifactBytes(cached) };
    }
    const manifest = await createSnapshot(core, id, request);
    core.manifests.set(request.migrationId, manifest);
    return { manifest, bytesTotal: totalArtifactBytes(manifest) };
}

export async function resumeMigration(core: WorkerCore, id: string, epoch: number): Promise<void> {
    if (core.record(id).info.state === SandboxState.Running) return;
    await resumeSandbox(core, id, epoch);
}
