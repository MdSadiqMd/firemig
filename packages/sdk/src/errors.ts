import { ErrorCode, FiremigError, isErrorEnvelope, type ErrorBody } from "@firemig/common";

export class ApiError extends FiremigError {
    constructor(body: ErrorBody, status?: number) {
        super(body, status);
        this.name = "ApiError";
    }
}

export class FencedError extends ApiError {
    constructor(body: ErrorBody, status?: number) {
        super(body, status);
        this.name = "FencedError";
    }
}

export class IdempotencyConflictError extends ApiError {
    constructor(body: ErrorBody, status?: number) {
        super(body, status);
        this.name = "IdempotencyConflictError";
    }
}

export class MigrationFailedError extends ApiError {
    readonly migrationId: string;

    constructor(migrationId: string, body: ErrorBody, status?: number) {
        super(body, status);
        this.name = "MigrationFailedError";
        this.migrationId = migrationId;
    }
}

export async function errorFromResponse(response: Response): Promise<ApiError> {
    let value: unknown;
    try {
        value = await response.json();
    } catch {
        value = undefined;
    }
    const body: ErrorBody = isErrorEnvelope(value)
        ? value.error
        : {
              code: `HTTP_${response.status}`,
              message: response.statusText || "API request failed",
              retryable: response.status >= 500,
          };
    if (body.code === ErrorCode.Fenced) return new FencedError(body, response.status);
    if (body.code === ErrorCode.IdempotencyKeyConflict)
        return new IdempotencyConflictError(body, response.status);
    return new ApiError(body, response.status);
}
