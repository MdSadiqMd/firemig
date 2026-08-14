import type { SandboxState } from "../protocol/phases.js";

export interface CreateSandboxRequest {
    region: string;
    cpu: number;
    memoryMb: number;
    kernel?: string;
    rootfs?: string;
    metadata?: Record<string, string>;
}

export interface PortExposure {
    guestPort: number;
    proxyHost: string;
    proxyPort: number;
    url: string;
}

export interface SandboxInfo {
    id: string;
    region: string;
    worker: string;
    state: SandboxState;
    epoch: number;
    cpu: number;
    memoryMb: number;
    createdAt: string;
    bootId?: string;
    bootedAt?: string;
    ports?: PortExposure[];
    activeMigrationId?: string;
}

export interface RunCommandRequest {
    command: string;
    background?: boolean;
    cwd?: string;
    env?: Record<string, string>;
    timeoutMs?: number;
}

export interface CommandResult {
    commandId: string;
    queued?: boolean;
    exitCode?: number;
    stdout?: string;
    stderr?: string;
    durationMs?: number;
    pid?: number;
}

export interface WriteFileRequest {
    path: string;
    content?: string;
    contentBase64?: string;
    mode?: number;
}

export interface WriteFileResult {
    path: string;
    bytes: number;
    sha256: string;
}

export interface ExposePortRequest {
    guestPort: number;
    protocol?: "tcp";
    sequenceAware?: boolean;
}
