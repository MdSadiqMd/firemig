import type { CompatibilityManifest, SandboxState } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";

export function workerBadRequest(message: string, details?: Record<string, unknown>): FiremigError {
    return new FiremigError(
        {
            code: ErrorCode.BadRequest,
            message,
            retryable: false,
            ...(details === undefined ? {} : { details }),
        },
        400,
    );
}

export function conflict(code: ErrorCode, message: string, status = 409): FiremigError {
    return new FiremigError({ code, message, retryable: false }, status);
}

export function sandboxNotFound(id: string): FiremigError {
    return new FiremigError(
        { code: ErrorCode.NotFound, message: `Sandbox ${id} was not found`, retryable: false },
        404,
    );
}

export function fencedError(id: string, requested: number, accepted: number): FiremigError {
    return new FiremigError(
        {
            code: ErrorCode.Fenced,
            message: `Sandbox ${id} is fenced`,
            retryable: false,
            details: { requestedEpoch: requested, acceptedEpoch: accepted },
        },
        409,
    );
}

export function stateMismatch(expected: SandboxState, actual: SandboxState): FiremigError {
    return new FiremigError(
        {
            code: ErrorCode.BadRequest,
            message: `Sandbox must be ${expected}; it is ${actual}`,
            retryable: false,
        },
        409,
    );
}

export function validateMachineSize(cpu: number, memoryMb: number): void {
    if (!Number.isInteger(cpu) || cpu < 1 || cpu > 32)
        throw workerBadRequest("cpu must be an integer from 1 to 32");
    if (!Number.isInteger(memoryMb) || memoryMb < 128 || memoryMb > 262_144)
        throw workerBadRequest("memoryMb must be an integer from 128 to 262144");
}

export function totalArtifactBytes(manifest: CompatibilityManifest): number {
    return Object.values(manifest.artifacts).reduce((total, artifact) => total + artifact.size, 0);
}
