import { dirname } from "node:path";
import type { CompatibilityManifest } from "@firemig/common";
import { ErrorCode, SandboxState } from "@firemig/common";
import type { WorkerCore } from "../core/worker-core.js";
import { conflict, fencedError, workerBadRequest } from "../core/worker-errors.js";
import { waitForGuest } from "../snapshot/worker-files.js";
import { validateManifest } from "../snapshot/worker-snapshot.js";
import { ARTIFACT_KINDS } from "../core/worker-types.js";

export async function pauseSandbox(core: WorkerCore, id: string, epoch: number): Promise<void> {
    const record = await core.mutableRecord(id, epoch);
    await record.firecracker.pause();
    record.info.state = SandboxState.Paused;
}

export async function loadSnapshot(
    core: WorkerCore,
    id: string,
    epoch: number,
    manifest: CompatibilityManifest,
): Promise<void> {
    validateManifest(core, manifest);
    if (manifest.sandboxId !== id) throw workerBadRequest("Manifest sandbox id does not match");
    if (epoch !== manifest.sourceEpoch + 1)
        throw conflict(ErrorCode.BadRequest, "Restore epoch must be exactly sourceEpoch + 1");
    if (core.consumedSnapshots.has(manifest.migrationId))
        throw conflict(ErrorCode.SnapshotConsumed, "Snapshot has already resumed once");

    const existing = core.record(id);
    if (
        existing.loadedMigrationId === manifest.migrationId &&
        existing.info.state === SandboxState.Paused
    )
        return;

    const record = await core.mutableRecord(id, epoch, SandboxState.Booting);
    for (const kind of ARTIFACT_KINDS) {
        const registered = record.artifacts[kind];
        const expected = manifest.artifacts[kind];
        if (registered?.sha256 !== expected.sha256 || registered.size !== expected.size)
            throw conflict(
                ErrorCode.ArtifactHashMismatch,
                `Verified ${kind} artifact is missing or does not match the manifest`,
                422,
            );
    }
    await record.firecracker.loadSnapshot({
        snapshotPath: record.paths.state,
        memoryPath: record.paths.memory,
        resume: false,
        clockRealtime: core.configuration.hostCompatibility.architecture === "x64",
    });
    record.loadedMigrationId = manifest.migrationId;
    record.info.state = SandboxState.Paused;
}

export async function resumeSandbox(core: WorkerCore, id: string, epoch: number): Promise<void> {
    const record = await core.mutableRecord(id, epoch, SandboxState.Paused);
    if (record.loadedMigrationId !== undefined) {
        if (core.consumedSnapshots.has(record.loadedMigrationId))
            throw conflict(ErrorCode.SnapshotConsumed, "Snapshot resume was already issued");
        core.consumedSnapshots.add(record.loadedMigrationId);
    }
    await record.firecracker.resume();
    record.info = { ...record.info, state: SandboxState.Running, epoch };
    await record.guest.syncClock();
    const ready = await waitForGuest(record.guest, 10_000);
    record.info = { ...record.info, bootId: ready.bootId };
}

export async function fenceSandbox(core: WorkerCore, id: string, epoch: number): Promise<void> {
    const record = core.record(id);
    await core.epochs.accept(id, epoch);
    const wasRunning = record.info.state === SandboxState.Running;
    record.info = { ...record.info, state: SandboxState.Fenced, epoch };
    await core.relays.stopSandbox(id);
    const actions: Promise<unknown>[] = [core.downHostVeth(record)];
    if (wasRunning) actions.push(record.firecracker.pause());
    const outcomes = await Promise.allSettled(actions);
    const failure = outcomes.find((outcome) => outcome.status === "rejected");
    if (failure?.status === "rejected") throw failure.reason;
}

export async function quarantineSandbox(
    core: WorkerCore,
    id: string,
    epoch: number,
    migrationId: string,
): Promise<string> {
    const record = core.record(id);
    if (record.info.state === SandboxState.Quarantined && record.quarantinePath !== undefined)
        return record.quarantinePath;
    await core.epochs.accept(id, epoch);
    if (epoch < record.info.epoch) throw fencedError(id, epoch, record.info.epoch);

    await core.lifecycle.stop(id);
    await core.relays.stopSandbox(id);
    await core.runCleanupPlans(record.netns, record.hostVeth);

    const destination = record.paths.quarantine(migrationId);
    await core.fs.mkdir(dirname(destination), { recursive: true });
    await core.fs.rename(record.paths.physicalDirectory, destination);
    record.info = { ...record.info, state: SandboxState.Quarantined, epoch };
    record.quarantinePath = destination;
    core.allocator.releaseNetwork(id, record.networkKeys);
    core.allocator.releasePorts(id);
    return destination;
}
