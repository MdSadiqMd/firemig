import type { ErrorBody } from "../protocol/errors.js";
import type { MigrationPath, MigrationPhase } from "../protocol/phases.js";

export interface MigrationOptions {
    deadlineMs?: number;
    quiesceGuest?: boolean;
    precopyDisk?: boolean;
    precopyRounds?: number;
    memoryPrecopy?: boolean;
    compression?: "auto" | "none";
}

export interface StartMigrationRequest {
    destination: string;
    options?: MigrationOptions;
}

export interface MigrationInfo {
    migrationId: string;
    sandboxId: string;
    phase: MigrationPhase;
    source?: string;
    destination?: string;
    epochBefore?: number;
    epochAfter?: number;
    bytesTransferred: number;
    bytesTotal: number;
    metrics?: MigrationMetrics;
    error?: ErrorBody;
}

export interface MigrationMetrics {
    totalMigrationMs?: number;
    vmPauseMs?: number;
    pathSelected?: MigrationPath;
    probeDirtyRate?: number;
    precopyBytes?: number;
    diskDeltaBytes?: number;
    snapshotCreateMs?: number;
    transferMs?: number;
    verifyMs?: number;
    loadMs?: number;
    resumeMs?: number;
}

export interface MigrationProgress {
    id?: string;
    phase: MigrationPhase;
    path?: MigrationPath;
    bytesTransferred: number;
    bytesTotal: number;
    ts: string;
    error?: ErrorBody;
}
