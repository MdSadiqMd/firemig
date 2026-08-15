import type { ArtifactDescriptor, ArtifactKind, CompatibilityManifest } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";
import { assertCompatible } from "../../artifacts/manifest.js";
import type { WorkerCore } from "../core/worker-core.js";
import type { SandboxRecord, SnapshotRequest } from "../core/worker-types.js";

export const TAP_NAME = "fmtap0";

export function buildManifest(
    core: WorkerCore,
    id: string,
    request: SnapshotRequest,
    record: SandboxRecord,
    artifacts: Record<ArtifactKind, ArtifactDescriptor>,
): CompatibilityManifest {
    const host = core.configuration.hostCompatibility;
    return {
        migrationId: request.migrationId,
        sandboxId: id,
        sourceEpoch: request.epoch,
        firecrackerVersion: host.firecrackerVersion,
        firecrackerDigest: host.firecrackerDigest,
        snapshotFormatVersion: host.snapshotFormatVersion,
        hostKernelVersion: host.hostKernelVersion,
        cpu: {
            architecture: host.architecture,
            vendor: host.cpuVendor,
            model: host.cpuModel,
            family: host.cpuFamily,
            stepping: host.cpuStepping,
        },
        guestKernelDigest: host.guestKernelDigest,
        cpuTemplate: host.cpuTemplate,
        vcpuCount: record.info.cpu,
        memSizeMib: record.info.memoryMb,
        smt: host.smt,
        hugePages: host.hugePages,
        driveCanonicalPath: record.paths.canonicalRootfs,
        tapName: TAP_NAME,
        vsockCanonicalPath: record.paths.canonicalVsock,
        artifacts,
        ports: record.info.ports ?? [],
        consumed: false,
    };
}

export function validateManifest(core: WorkerCore, manifest: CompatibilityManifest): void {
    assertCompatible(manifest, core.configuration.hostCompatibility);
    const record = core.sandboxes.get(manifest.sandboxId);
    if (record === undefined) return;

    const problems: string[] = [];
    if (manifest.vcpuCount !== record.info.cpu)
        problems.push("vcpu_count does not match the destination reservation");
    if (manifest.memSizeMib !== record.info.memoryMb)
        problems.push("mem_size_mib does not match the destination reservation");
    if (manifest.driveCanonicalPath !== record.paths.canonicalRootfs)
        problems.push("canonical drive path does not match");
    if (manifest.vsockCanonicalPath !== record.paths.canonicalVsock)
        problems.push("canonical vsock path does not match");
    if (manifest.tapName !== TAP_NAME) problems.push("TAP name does not match");
    if (problems.length > 0) {
        throw new FiremigError(
            {
                code: ErrorCode.IncompatibleDestination,
                message: "Snapshot resources do not match the destination reservation",
                retryable: false,
                details: { problems },
            },
            412,
        );
    }
}
