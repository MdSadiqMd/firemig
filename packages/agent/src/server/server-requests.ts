import { ErrorCode, FiremigError } from "@firemig/common";
import type { FastifyRequest } from "fastify";
import type { PrepareMigrationRequest } from "../worker/index.js";

export function epoch(request: FastifyRequest): number {
    const value = request.headers["x-firemig-epoch"];
    const parsed = typeof value === "string" && /^\d+$/.test(value) ? Number(value) : Number.NaN;
    if (!Number.isSafeInteger(parsed)) {
        throw new FiremigError(
            {
                code: ErrorCode.BadRequest,
                message: "X-Firemig-Epoch must be a non-negative integer",
                retryable: false,
            },
            400,
        );
    }
    return parsed;
}

export function normalizePrepareRequest(
    id: string,
    migrationId: string,
    body: Record<string, unknown>,
): PrepareMigrationRequest {
    const sandbox = body.sandbox;
    if (typeof sandbox !== "object" || sandbox === null) throw badRequest("sandbox is required");
    const values = sandbox as Record<string, unknown>;
    const stage = body.stage;
    if (stage !== "reserve" && stage !== "prestage")
        throw badRequest("stage must be reserve or prestage");
    const cpu = requiredInteger(values.cpu, "sandbox.cpu");
    const memoryMb = requiredInteger(values.memoryMb ?? values.memory_mb, "sandbox.memoryMb");
    const bootId = values.bootId ?? values.boot_id;
    const bodyMigrationId = requiredString(
        body.migrationId ?? body.migration_id ?? migrationId,
        "migrationId",
    );
    if (bodyMigrationId !== migrationId) throw badRequest("migrationId does not match route");
    return {
        migrationId: bodyMigrationId,
        stage,
        source: requiredString(body.source, "source"),
        destination: requiredString(body.destination, "destination"),
        sandbox: {
            id: requiredString(values.id ?? id, "sandbox.id"),
            cpu,
            memoryMb,
            ...(bootId === undefined || bootId === null
                ? {}
                : { bootId: requiredString(bootId, "sandbox.bootId") }),
        },
    };
}

export function requiredString(value: unknown, field: string): string {
    if (typeof value !== "string" || value === "")
        throw badRequest(`${field} must be a non-empty string`);
    return value;
}

export function requiredInteger(value: unknown, field: string): number {
    if (!Number.isSafeInteger(value)) throw badRequest(`${field} must be an integer`);
    return value as number;
}

export function badRequest(message: string): FiremigError {
    return new FiremigError({ code: ErrorCode.BadRequest, message, retryable: false }, 400);
}
