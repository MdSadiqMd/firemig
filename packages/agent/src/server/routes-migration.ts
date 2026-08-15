import type { CompatibilityManifest } from "@firemig/common";
import type { FastifyInstance } from "fastify";
import type { AgentServerOptions, IdParams, MigrationParams } from "./server-context.js";
import { epoch, normalizePrepareRequest, requiredString } from "./server-requests.js";

/** Body shape shared by the phases the coordinator addresses by migration id. */
interface MigrationIdBody {
    migrationId?: string;
    migration_id?: string;
}

export function registerMigrationRoutes(app: FastifyInstance, options: AgentServerOptions): void {
    app.post<{ Params: MigrationParams; Body: Record<string, unknown> }>(
        "/internal/sandboxes/:id/migrations/:migrationId/prepare",
        async (request) =>
            options.worker.prepareMigration(
                request.params.id,
                epoch(request),
                normalizePrepareRequest(
                    request.params.id,
                    request.params.migrationId,
                    request.body,
                ),
            ),
    );

    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/migration/probe", async (request) =>
        options.worker.probeMigration(request.params.id, epoch(request)),
    );

    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/migration/precopy", async (request) =>
        options.worker.precopyMigration(request.params.id, epoch(request)),
    );

    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/migration/pause", async (request) => {
        await options.worker.pauseMigration(request.params.id, epoch(request));
        return { state: "paused" };
    });

    app.post<{ Params: IdParams; Body: MigrationIdBody }>(
        "/internal/sandboxes/:id/migration/snapshot",
        async (request) =>
            options.worker.snapshotMigration(request.params.id, {
                migrationId: migrationId(request.body),
                epoch: epoch(request),
            }),
    );

    app.post<{
        Params: IdParams;
        Body: MigrationIdBody & { source: string; manifest: CompatibilityManifest };
    }>("/internal/sandboxes/:id/migration/transfer", async (request) =>
        options.worker.transferMigration(request.params.id, epoch(request), {
            migrationId: migrationId(request.body),
            source: requiredString(request.body.source, "source"),
            manifest: request.body.manifest,
        }),
    );

    app.post<{ Params: IdParams; Body: { manifest: CompatibilityManifest } }>(
        "/internal/sandboxes/:id/migration/load",
        async (request) => {
            await options.worker.load(request.params.id, epoch(request), request.body.manifest);
            return { state: "paused" };
        },
    );

    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/migration/resume", async (request) => {
        await options.worker.resumeMigration(request.params.id, epoch(request));
        return { state: "running" };
    });

    app.post<{ Params: IdParams; Body: MigrationIdBody }>(
        "/internal/sandboxes/:id/migration/verify",
        async (request) =>
            options.worker.verifyMigration(
                request.params.id,
                epoch(request),
                migrationId(request.body),
            ),
    );

    app.post<{ Params: IdParams; Body: { repairClock?: boolean } }>(
        "/internal/sandboxes/:id/migration/rollback",
        async (request) => {
            await options.worker.rollbackMigration(
                request.params.id,
                epoch(request),
                request.body.repairClock ?? true,
            );
            return { state: "running", rolledBack: true };
        },
    );

    app.post<{ Params: IdParams; Body: MigrationIdBody }>(
        "/internal/sandboxes/:id/migration/fence-and-cleanup",
        async (request) => {
            const path = await options.worker.fenceAndCleanup(
                request.params.id,
                epoch(request),
                migrationId(request.body),
            );
            return { state: "quarantined", path };
        },
    );
}

function migrationId(body: MigrationIdBody): string {
    return requiredString(body.migrationId ?? body.migration_id, "migrationId");
}
