import { ErrorCode } from "@firemig/common";
import type { WorkerCore } from "../core/worker-core.js";
import { conflict, workerBadRequest } from "../core/worker-errors.js";
import type { MigrationReservation, PrepareMigrationRequest } from "../core/worker-types.js";

export async function prepareMigration(
    core: WorkerCore,
    id: string,
    epoch: number,
    request: PrepareMigrationRequest,
): Promise<Record<string, unknown>> {
    if (request.sandbox.id !== id)
        throw workerBadRequest("Prepared sandbox id does not match route");
    if (request.destination !== core.configuration.workerId)
        throw workerBadRequest("Migration destination does not match this worker");

    const key = `${id}:${request.migrationId}`;
    const prior = core.migrations.get(key);
    if (prior !== undefined && conflictsWithPrior(prior, epoch, request))
        throw conflict(ErrorCode.IdempotencyKeyConflict, "Migration reservation payload changed");

    const reservation: MigrationReservation = prior ?? { ...request, epoch, prepared: false };
    core.migrations.set(key, reservation);
    if (request.stage === "prestage" && !reservation.prepared) {
        reservation.preparing ??= ensureDestinationReservation(core, id, epoch, request)
            .then(() => {
                reservation.prepared = true;
            })
            .finally(() => {
                delete reservation.preparing;
            });
        await reservation.preparing;
    }
    return {
        migrationId: request.migrationId,
        stage: request.stage,
        reserved: true,
        prestaged: reservation.prepared,
        dependenciesReady: true,
        prestageReady: reservation.prepared && core.lifecycle.running(id),
        worker: core.configuration.workerId,
        state: core.sandboxes.get(id)?.info.state ?? "reserved",
    };
}

function conflictsWithPrior(
    prior: MigrationReservation,
    epoch: number,
    request: PrepareMigrationRequest,
): boolean {
    return (
        prior.epoch !== epoch ||
        prior.source !== request.source ||
        prior.destination !== request.destination ||
        prior.sandbox.cpu !== request.sandbox.cpu ||
        prior.sandbox.memoryMb !== request.sandbox.memoryMb
    );
}

/**
 * Creates the destination sandbox in `restore` mode on first prestage, and on retry
 * asserts the existing reservation still matches so a changed payload cannot slip through.
 */
async function ensureDestinationReservation(
    core: WorkerCore,
    id: string,
    epoch: number,
    request: PrepareMigrationRequest,
): Promise<void> {
    const existing = core.sandboxes.get(id);
    if (existing === undefined) {
        await core.createSandbox({
            id,
            epoch,
            cpu: request.sandbox.cpu,
            memoryMb: request.sandbox.memoryMb,
            mode: "restore",
        });
        return;
    }
    if (
        existing.info.epoch !== epoch ||
        existing.info.cpu !== request.sandbox.cpu ||
        existing.info.memoryMb !== request.sandbox.memoryMb
    ) {
        throw conflict(
            ErrorCode.IdempotencyKeyConflict,
            "Destination sandbox reservation conflicts with prepare request",
        );
    }
}
