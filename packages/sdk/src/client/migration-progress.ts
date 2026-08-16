import { ErrorCode, MigrationPhase, type MigrationProgress } from "@firemig/common";
import { ApiError } from "../errors.js";

export function parseProgress(data: string, id?: string): MigrationProgress {
    const value = JSON.parse(data) as Partial<MigrationProgress>;
    if (typeof value.phase !== "string" || typeof value.bytesTransferred !== "number") {
        throw new ApiError({
            code: ErrorCode.BadRequest,
            message: "Invalid migration progress event",
            retryable: false,
        });
    }
    return {
        ...value,
        phase: value.phase as MigrationPhase,
        bytesTransferred: value.bytesTransferred,
        bytesTotal: typeof value.bytesTotal === "number" ? value.bytesTotal : 0,
        ts: value.ts ?? new Date().toISOString(),
        ...(id === undefined ? {} : { id }),
    };
}

export function isFailure(phase: MigrationPhase): boolean {
    return (
        phase === MigrationPhase.Failed ||
        phase === MigrationPhase.RolledBack ||
        phase === MigrationPhase.OrphanedAmbiguous
    );
}
