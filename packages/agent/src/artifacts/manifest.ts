import type { CompatibilityManifest } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";

export interface HostCompatibility {
    firecrackerVersion: string;
    firecrackerDigest: string;
    snapshotFormatVersion: string;
    hostKernelVersion: string;
    architecture: string;
    cpuVendor: string;
    cpuModel: string;
    cpuFamily: string;
    cpuStepping: string;
    guestKernelDigest: string;
    cpuTemplate: string;
    smt: boolean;
    hugePages: "None" | "2M";
}

export function compatibilityProblems(
    manifest: CompatibilityManifest,
    host: HostCompatibility,
): string[] {
    const checks: Array<[string, unknown, unknown]> = [
        ["Firecracker version", manifest.firecrackerVersion, host.firecrackerVersion],
        ["Firecracker digest", manifest.firecrackerDigest, host.firecrackerDigest],
        ["snapshot format", manifest.snapshotFormatVersion, host.snapshotFormatVersion],
        ["host kernel", manifest.hostKernelVersion, host.hostKernelVersion],
        ["CPU architecture", manifest.cpu.architecture, host.architecture],
        ["CPU vendor", manifest.cpu.vendor, host.cpuVendor],
        ["CPU model", manifest.cpu.model, host.cpuModel],
        ["CPU family", manifest.cpu.family, host.cpuFamily],
        ["CPU stepping", manifest.cpu.stepping, host.cpuStepping],
        ["guest kernel", manifest.guestKernelDigest, host.guestKernelDigest],
        ["CPU template", manifest.cpuTemplate, host.cpuTemplate],
        ["SMT", manifest.smt, host.smt],
        ["huge pages", manifest.hugePages, host.hugePages],
    ];
    return checks
        .filter(([, source, destination]) => source !== destination)
        .map(
            ([name, source, destination]) =>
                `${name}: source=${String(source)} destination=${String(destination)}`,
        );
}

export function assertCompatible(manifest: CompatibilityManifest, host: HostCompatibility): void {
    if (manifest.consumed) {
        throw new FiremigError(
            {
                code: ErrorCode.SnapshotConsumed,
                message: "Snapshot has already been consumed",
                retryable: false,
            },
            409,
        );
    }
    const problems = compatibilityProblems(manifest, host);
    if (problems.length > 0) {
        throw new FiremigError(
            {
                code: ErrorCode.IncompatibleDestination,
                message: "Destination is incompatible with the snapshot",
                retryable: false,
                details: { problems },
            },
            412,
        );
    }
}
