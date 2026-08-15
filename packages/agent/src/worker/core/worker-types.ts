import type {
    ArtifactDescriptor,
    ArtifactKind,
    CompatibilityManifest,
    SandboxInfo,
} from "@firemig/common";
import type { FirecrackerClient } from "../../runtime/firecracker.js";
import type { HostCompatibility } from "../../artifacts/manifest.js";
import type { SandboxPaths } from "../../platform/paths.js";
import type { VsockGuestClient } from "../../runtime/vsock.js";

export interface WorkerConfiguration {
    workerId: string;
    region: string;
    workerRoot: string;
    canonicalRoot?: string;
    firecrackerBinary: string;
    kernelPath: string;
    baseRootfsPath: string;
    proxyHost: string;
    portBase?: number;
    peerUrls?: Readonly<Record<string, string>>;
    peerAuthToken?: string;
    sharedWorkerRoot?: string;
    hostCompatibility: HostCompatibility;
}

export interface CreateWorkerSandboxRequest {
    id: string;
    epoch: number;
    cpu: number;
    memoryMb: number;
    mode?: "boot" | "restore";
    kernelPath?: string;
    rootfsPath?: string;
    kernel?: string;
    rootfs?: string;
    netns?: string;
    hostVeth?: string;
    hostAddress?: string;
    namespaceAddress?: string;
    mtu?: number;
}

export interface SandboxRecord {
    info: SandboxInfo;
    paths: SandboxPaths;
    netns: string;
    hostVeth: string;
    namespaceAddress: string;
    guest: VsockGuestClient;
    firecracker: FirecrackerClient;
    generation: number;
    artifacts: Partial<Record<ArtifactKind, ArtifactDescriptor>>;
    loadedMigrationId?: string;
    networkKeys: readonly string[];
    quarantinePath?: string;
}

export interface SnapshotRequest {
    migrationId: string;
    epoch: number;
}

export interface PrepareMigrationRequest {
    migrationId: string;
    stage: "reserve" | "prestage";
    source: string;
    destination: string;
    sandbox: { id: string; cpu: number; memoryMb: number; bootId?: string };
}

export interface MigrationReservation extends PrepareMigrationRequest {
    epoch: number;
    prepared: boolean;
    preparing?: Promise<void>;
}

export interface TransferMigrationRequest {
    migrationId: string;
    source: string;
    manifest: CompatibilityManifest;
}

export const ARTIFACT_KINDS = ["state", "mem", "disk"] as const;
