export enum MigrationPhase {
    Preparing = "PREPARING",
    Reserving = "RESERVING",
    Prestaging = "PRESTAGING",
    Probing = "PROBING",
    Precopying = "PRECOPYING",
    Pausing = "PAUSING",
    Snapshotting = "SNAPSHOTTING",
    Transferring = "TRANSFERRING",
    Loading = "LOADING",
    Resuming = "RESUMING",
    Verifying = "VERIFYING",
    Cutover = "CUTOVER",
    Cleanup = "CLEANUP",
    Done = "DONE",
    RollingBackSource = "ROLLING_BACK_SOURCE",
    RolledBack = "ROLLED_BACK",
    Failed = "FAILED",
    OrphanedAmbiguous = "ORPHANED_AMBIGUOUS",
}

export enum SandboxState {
    Booting = "booting",
    Running = "running",
    Paused = "paused",
    Fenced = "fenced",
    Quarantined = "quarantined",
    Failed = "failed",
}

export enum MigrationPath {
    Idle = "IDLE",
    Quiet = "QUIET",
    Busy = "BUSY",
}

const terminalPhases = new Set<MigrationPhase>([
    MigrationPhase.Done,
    MigrationPhase.RolledBack,
    MigrationPhase.Failed,
    MigrationPhase.OrphanedAmbiguous,
]);

export function isTerminalPhase(phase: MigrationPhase): boolean {
    return terminalPhases.has(phase);
}
