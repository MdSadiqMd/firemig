import type { ArtifactDescriptor, ArtifactKind } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";
import type { WorkerCore } from "../core/worker-core.js";
import type { SandboxRecord } from "../core/worker-types.js";

export function artifactPath(record: SandboxRecord, kind: ArtifactKind): string {
    if (kind === "state") return record.paths.state;
    if (kind === "mem") return record.paths.memory;
    return record.paths.physicalRootfs;
}

export function readArtifact(
    core: WorkerCore,
    id: string,
    kind: ArtifactKind,
): { path: string; descriptor: ArtifactDescriptor } {
    const record = core.record(id);
    const descriptor = record.artifacts[kind];
    if (descriptor === undefined)
        throw new FiremigError(
            {
                code: ErrorCode.NotFound,
                message: `Artifact ${kind} is unavailable`,
                retryable: false,
            },
            404,
        );
    return { path: artifactPath(record, kind), descriptor };
}
