import { ErrorCode, FiremigError, SandboxState } from "@firemig/common";
import type { WorkerCore } from "../core/worker-core.js";
import { conflict } from "../core/worker-errors.js";
import { fenceSandbox, quarantineSandbox, resumeSandbox } from "../lifecycle/worker-lifecycle.js";

export async function verifyMigration(
    core: WorkerCore,
    id: string,
    epoch: number,
    migrationId: string,
): Promise<Record<string, unknown>> {
    const record = await core.mutableRecord(id, epoch, SandboxState.Running);
    const ready = await record.guest.ready();
    const expected =
        core.migrations.get(`${id}:${migrationId}`)?.sandbox.bootId ?? record.info.bootId;
    if (expected !== undefined && ready.bootId !== expected) {
        throw new FiremigError(
            {
                code: ErrorCode.GuestAgent,
                message: "Restored guest boot ID does not match the source",
                retryable: false,
                details: { expectedBootId: expected, actualBootId: ready.bootId },
            },
            409,
        );
    }
    return {
        healthy: true,
        bootId: ready.bootId,
        expectedBootId: expected,
        ports: record.info.ports ?? [],
    };
}

export async function rollbackMigration(
    core: WorkerCore,
    id: string,
    epoch: number,
    repairClock: boolean,
): Promise<void> {
    const record = core.record(id);
    if (record.loadedMigrationId !== undefined)
        throw conflict(ErrorCode.Fenced, "Rollback may only resume the source VM");
    if (record.info.state === SandboxState.Paused) {
        await resumeSandbox(core, id, epoch);
        return;
    }
    if (record.info.state !== SandboxState.Running) {
        throw new FiremigError(
            {
                code: ErrorCode.BadRequest,
                message: `Cannot roll back sandbox in ${record.info.state}`,
                retryable: false,
            },
            409,
        );
    }
    if (repairClock) await record.guest.syncClock();
}

export async function fenceAndCleanup(
    core: WorkerCore,
    id: string,
    epoch: number,
    migrationId: string,
): Promise<string> {
    const record = core.record(id);
    if (record.info.state === SandboxState.Quarantined && record.quarantinePath !== undefined)
        return record.quarantinePath;
    await fenceSandbox(core, id, epoch);
    return quarantineSandbox(core, id, epoch, migrationId);
}
