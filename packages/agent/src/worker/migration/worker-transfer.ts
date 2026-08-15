import { basename, resolve, sep } from "node:path";
import type { ArtifactDescriptor } from "@firemig/common";
import { ErrorCode, FiremigError, SandboxState } from "@firemig/common";
import { assertIdentifier } from "../../platform/paths.js";
import { pullArtifact, runAbortableOperations } from "../../artifacts/transfer.js";
import type { WorkerCore } from "../core/worker-core.js";
import { totalArtifactBytes, workerBadRequest } from "../core/worker-errors.js";
import { exposeGuestPort } from "../lifecycle/worker-guest-ops.js";
import { artifactPath, validateManifest } from "../snapshot/worker-snapshot.js";
import { ARTIFACT_KINDS, type TransferMigrationRequest } from "../core/worker-types.js";

export async function transferMigration(
    core: WorkerCore,
    id: string,
    epoch: number,
    request: TransferMigrationRequest,
): Promise<{ bytesTotal: number; bytesTransferred: number }> {
    if (request.manifest.migrationId !== request.migrationId)
        throw workerBadRequest("Transfer migration id does not match manifest");

    validateManifest(core, request.manifest);
    await core.mutableRecord(id, epoch, SandboxState.Booting);

    const sourceUrl = core.configuration.peerUrls?.[request.source];
    if (sourceUrl === undefined) {
        throw new FiremigError(
            {
                code: ErrorCode.DestinationUnavailable,
                message: `No peer URL configured for ${request.source}`,
                retryable: true,
            },
            503,
        );
    }

    const complete = ARTIFACT_KINDS.every((kind) => {
        const actual = core.record(id).artifacts[kind];
        const expected = request.manifest.artifacts[kind];
        return actual?.size === expected.size && actual.sha256 === expected.sha256;
    });
    if (!complete) {
        await runAbortableOperations(
            ARTIFACT_KINDS.map((kind) => async (signal: AbortSignal) => {
                const descriptor = request.manifest.artifacts[kind];
                await transferArtifact(core, id, request.source, sourceUrl, descriptor, signal);
                core.record(id).artifacts[descriptor.kind] = descriptor;
            }),
        );
    }
    for (const port of request.manifest.ports ?? [])
        await exposeGuestPort(core, id, epoch, port.guestPort);

    const bytesTotal = totalArtifactBytes(request.manifest);
    return { bytesTotal, bytesTransferred: bytesTotal };
}

async function transferArtifact(
    core: WorkerCore,
    id: string,
    sourceWorker: string,
    sourceUrl: string,
    descriptor: ArtifactDescriptor,
    signal: AbortSignal,
): Promise<void> {
    const destinationPath = artifactPath(core.record(id), descriptor.kind);
    const sharedRoot = core.configuration.sharedWorkerRoot;
    if (sharedRoot === undefined) {
        const base = sourceUrl.replace(/\/$/, "");
        const path = `/internal/sandboxes/${encodeURIComponent(id)}/artifacts/${descriptor.kind}`;
        const token = core.configuration.peerAuthToken;
        await pullArtifact({
            url: `${base}${path}`,
            destinationPath,
            descriptor,
            fs: core.fs,
            signal,
            ...(core.artifactHttp === undefined ? {} : { http: core.artifactHttp }),
            ...(token === undefined ? {} : { headers: { authorization: `Bearer ${token}` } }),
        });
        return;
    }
    signal.throwIfAborted();
    await linkSharedArtifact(core, id, sourceWorker, sharedRoot, destinationPath, descriptor);
    signal.throwIfAborted();
}

/** Single-host deployments share a root, so an artifact is hard-linked rather than copied. */
async function linkSharedArtifact(
    core: WorkerCore,
    id: string,
    sourceWorker: string,
    sharedRoot: string,
    destinationPath: string,
    descriptor: ArtifactDescriptor,
): Promise<void> {
    assertIdentifier(sourceWorker, "source worker");
    if (basename(descriptor.name) !== descriptor.name) throw new Error("Invalid artifact name");
    const sourceBase = resolve(sharedRoot, sourceWorker, "sandboxes", id);
    const sourcePath = resolve(sourceBase, descriptor.name);
    if (!sourcePath.startsWith(`${sourceBase}${sep}`))
        throw new Error("Artifact path escaped source sandbox");

    const partialPath = `${destinationPath}.partial`;
    await core.fs.rm(partialPath, { force: true });
    await core.fs.link(sourcePath, partialPath);
    const stat = await core.fs.stat(partialPath);
    if (stat.size !== descriptor.size)
        throw new Error(`Shared ${descriptor.kind} artifact size changed`);
    await core.fs.rename(partialPath, destinationPath);
}
