export enum ErrorCode {
    BadRequest = "BAD_REQUEST",
    NotFound = "NOT_FOUND",
    Internal = "INTERNAL",
    FirecrackerApi = "FIRECRACKER_API_ERROR",
    GuestAgent = "GUEST_AGENT_ERROR",
    Fenced = "FENCED",
    MigrationBarrier = "MIGRATION_BARRIER",
    MigrationInProgress = "MIGRATION_IN_PROGRESS",
    IdempotencyKeyConflict = "IDEMPOTENCY_KEY_CONFLICT",
    IncompatibleDestination = "INCOMPATIBLE_DESTINATION",
    NoCapacity = "NO_CAPACITY",
    TransferInterrupted = "TRANSFER_INTERRUPTED",
    ArtifactHashMismatch = "ARTIFACT_HASH_MISMATCH",
    ArtifactRangeInvalid = "ARTIFACT_RANGE_INVALID",
    SnapshotConsumed = "SNAPSHOT_CONSUMED",
    DestinationUnavailable = "DESTINATION_UNAVAILABLE",
    Timeout = "TIMEOUT",
}

export interface ErrorBody {
    code: ErrorCode | string;
    message: string;
    retryable: boolean;
    details?: Record<string, unknown>;
}

export interface ErrorEnvelope {
    error: ErrorBody;
}

export class FiremigError extends Error {
    readonly code: ErrorCode | string;
    readonly retryable: boolean;
    readonly details: Record<string, unknown> | undefined;
    readonly status: number | undefined;

    constructor(body: ErrorBody, status?: number) {
        super(body.message);
        this.name = "FiremigError";
        this.code = body.code;
        this.retryable = body.retryable;
        this.details = body.details;
        this.status = status;
    }
}

export function errorEnvelope(
    code: ErrorCode | string,
    message: string,
    retryable = false,
    details?: Record<string, unknown>,
): ErrorEnvelope {
    return { error: { code, message, retryable, ...(details === undefined ? {} : { details }) } };
}

export function isErrorEnvelope(value: unknown): value is ErrorEnvelope {
    if (typeof value !== "object" || value === null || !("error" in value)) return false;
    const error = (value as { error?: unknown }).error;
    return (
        typeof error === "object" &&
        error !== null &&
        typeof (error as { code?: unknown }).code === "string" &&
        typeof (error as { message?: unknown }).message === "string" &&
        typeof (error as { retryable?: unknown }).retryable === "boolean"
    );
}
