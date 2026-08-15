import type { CompatibilityManifest } from "@firemig/common";
import type { FastifyInstance } from "fastify";
import { openArtifactRange } from "../artifacts/artifact-range.js";
import type { AgentServerOptions, ArtifactParams, IdParams } from "./server-context.js";
import { epoch } from "./server-requests.js";
import { pullArtifact, runAbortableOperations } from "../artifacts/transfer.js";

const ARTIFACT_KINDS = ["state", "mem", "disk"] as const;

export function registerArtifactRoutes(app: FastifyInstance, options: AgentServerOptions): void {
    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/pause", async (request) => {
        await options.worker.pause(request.params.id, epoch(request));
        return { state: "paused" };
    });

    app.post<{ Params: IdParams; Body: { migrationId: string } }>(
        "/internal/sandboxes/:id/snapshot",
        async (request) =>
            options.worker.snapshot(request.params.id, {
                migrationId: request.body.migrationId,
                epoch: epoch(request),
            }),
    );

    app.post<{
        Params: IdParams;
        Body: { manifest: CompatibilityManifest; sourceBaseUrl: string };
    }>("/internal/sandboxes/:id/artifacts/pull", async (request) => {
        const { id } = request.params;
        options.worker.validateManifest(request.body.manifest);
        const authorization = request.headers.authorization;
        const base = request.body.sourceBaseUrl.replace(/\/$/, "");
        const results = await runAbortableOperations(
            ARTIFACT_KINDS.map((kind) => async (signal: AbortSignal) => {
                const descriptor = request.body.manifest.artifacts[kind];
                const result = await pullArtifact({
                    url: `${base}/internal/sandboxes/${encodeURIComponent(id)}/artifacts/${kind}`,
                    destinationPath: options.worker.destinationArtifactPath(id, kind),
                    descriptor,
                    fs: options.fs,
                    signal,
                    ...(options.artifactHttp === undefined ? {} : { http: options.artifactHttp }),
                    ...(authorization === undefined ? {} : { headers: { authorization } }),
                });
                options.worker.registerArtifact(id, descriptor);
                return { kind, ...result };
            }),
        );
        return { artifacts: results };
    });

    app.get<{ Params: ArtifactParams }>(
        "/internal/sandboxes/:id/artifacts/:kind",
        async (request, reply) => {
            const artifact = options.worker.artifact(request.params.id, request.params.kind);
            const result = await openArtifactRange(
                options.fs,
                artifact.path,
                artifact.descriptor,
                request.headers.range,
            );
            return reply.code(result.status).headers(result.headers).send(result.stream);
        },
    );

    app.post<{ Params: IdParams; Body: { manifest: CompatibilityManifest } }>(
        "/internal/sandboxes/:id/load",
        async (request) => {
            await options.worker.load(request.params.id, epoch(request), request.body.manifest);
            return { state: "paused" };
        },
    );

    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/resume", async (request) => {
        await options.worker.resume(request.params.id, epoch(request));
        return { state: "running" };
    });

    app.post<{ Params: IdParams }>("/internal/sandboxes/:id/fence", async (request) => {
        await options.worker.fence(request.params.id, epoch(request));
        return { state: "fenced" };
    });

    app.post<{ Params: IdParams; Body: { migrationId: string } }>(
        "/internal/sandboxes/:id/quarantine",
        async (request) => {
            const path = await options.worker.quarantine(
                request.params.id,
                epoch(request),
                request.body.migrationId,
            );
            return { state: "quarantined", path };
        },
    );
}
