import type { PortExposure } from "./sandbox.js";

export type ArtifactKind = "state" | "mem" | "disk";

export interface ArtifactDescriptor {
    kind: ArtifactKind;
    name: string;
    size: number;
    sha256: string;
}

export interface CpuFingerprint {
    architecture: string;
    vendor: string;
    model: string;
    family: string;
    stepping: string;
}

export interface CompatibilityManifest {
    migrationId: string;
    sandboxId: string;
    sourceEpoch: number;
    firecrackerVersion: string;
    firecrackerDigest: string;
    snapshotFormatVersion: string;
    hostKernelVersion: string;
    cpu: CpuFingerprint;
    guestKernelDigest: string;
    cpuTemplate: string;
    vcpuCount: number;
    memSizeMib: number;
    smt: boolean;
    hugePages: "None" | "2M";
    driveCanonicalPath: string;
    tapName: string;
    vsockCanonicalPath: string;
    artifacts: Record<ArtifactKind, ArtifactDescriptor>;
    ports?: PortExposure[];
    consumed: boolean;
}
