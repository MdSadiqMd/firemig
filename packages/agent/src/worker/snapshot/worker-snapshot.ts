import type { ArtifactDescriptor, ArtifactKind, CompatibilityManifest } from "@firemig/common";
import { ErrorCode, FiremigError, SandboxState } from "@firemig/common";
import { assertCompatible } from "../../artifacts/manifest.js";
import type { WorkerCore } from "../core/worker-core.js";
import { describeArtifact, describeSharedArtifact, syncSnapshotFiles } from "./worker-files.js";
import type { SandboxRecord, SnapshotRequest } from "../core/worker-types.js";
import { buildManifest } from "./worker-manifest.js";

export { artifactPath, readArtifact } from "./worker-artifact-paths.js";
export { TAP_NAME, validateManifest } from "./worker-manifest.js";

export async function createSnapshot(
    core: WorkerCore,
    id: string,
    request: SnapshotRequest,
): Promise<CompatibilityManifest> {
    const record = await core.mutableRecord(id, request.epoch, SandboxState.Paused);
    record.generation += 1;
    const generatedPaths = core.paths.sandbox(id, record.generation);
    await record.firecracker.createSnapshot(generatedPaths.state, generatedPaths.memory);

    const shared = core.configuration.sharedWorkerRoot !== undefined;
    if (!shared) {
        await syncSnapshotFiles(core.fs, [
            generatedPaths.state,
            generatedPaths.memory,
            record.paths.physicalRootfs,
        ]);
    }
    const describe = (kind: ArtifactKind, path: string): Promise<ArtifactDescriptor> =>
        shared
            ? describeSharedArtifact(core.fs, kind, path)
            : describeArtifact(core.fs, kind, path);
    const [state, memory, disk] = await Promise.all([
        describe("state", generatedPaths.state),
        describe("mem", generatedPaths.memory),
        describe("disk", record.paths.physicalRootfs),
    ]);

    record.paths = generatedPaths;
    record.artifacts = { state, mem: memory, disk };
    return buildManifest(core, id, request, record, { state, mem: memory, disk });
}
