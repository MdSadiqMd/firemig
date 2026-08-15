import type { RunCommandRequest, WriteFileRequest } from "@firemig/common";
import type { FastifyInstance } from "fastify";
import type { AgentServerOptions, IdParams } from "./server-context.js";
import { epoch } from "./server-requests.js";
import type { CreateWorkerSandboxRequest } from "../worker/index.js";

export function registerSandboxRoutes(app: FastifyInstance, options: AgentServerOptions): void {
    app.get("/healthz", async () => ({ ok: true }));

    app.post<{ Body: CreateWorkerSandboxRequest }>(
        "/internal/sandboxes",
        async (request, reply) => {
            const result = await options.worker.create(request.body);
            return reply.code(201).send(result);
        },
    );

    app.get<{ Params: IdParams }>("/internal/sandboxes/:id", async (request) =>
        options.worker.get(request.params.id),
    );

    app.post<{ Params: IdParams; Body: RunCommandRequest }>(
        "/internal/sandboxes/:id/commands",
        async (request, reply) => {
            const result = await options.worker.command(
                request.params.id,
                epoch(request),
                request.body,
            );
            return reply.code(request.body.background === true ? 202 : 200).send(result);
        },
    );

    app.put<{ Params: IdParams; Body: WriteFileRequest }>(
        "/internal/sandboxes/:id/files",
        async (request) =>
            options.worker.writeFile(request.params.id, epoch(request), request.body),
    );

    app.post<{ Params: IdParams; Body: { guestPort: number } }>(
        "/internal/sandboxes/:id/ports",
        async (request, reply) => {
            const result = await options.worker.exposePort(
                request.params.id,
                epoch(request),
                request.body.guestPort,
            );
            return reply.code(201).send(result);
        },
    );
}
