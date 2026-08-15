import { timingSafeEqual } from "node:crypto";
import { ErrorCode, errorEnvelope, FiremigError } from "@firemig/common";
import Fastify, { type FastifyInstance } from "fastify";
import { registerArtifactRoutes } from "./routes-artifacts.js";
import { registerMigrationRoutes } from "./routes-migration.js";
import { registerSandboxRoutes } from "./routes-sandbox.js";
import type { AgentServerOptions } from "./server-context.js";

export type { AgentServerOptions } from "./server-context.js";

export function buildAgentServer(options: AgentServerOptions): FastifyInstance {
    const app = Fastify({
        logger: options.logger ?? true,
        bodyLimit: 16 * 1024 * 1024,
        requestTimeout: 35_000,
    });

    app.addHook("onRequest", async (request, reply) => {
        if (options.authToken === undefined || request.url === "/healthz") return;
        const expected = Buffer.from(`Bearer ${options.authToken}`);
        const actual = Buffer.from(request.headers.authorization ?? "");
        if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
            return reply.code(401).send(errorEnvelope(ErrorCode.BadRequest, "Unauthorized"));
        }
    });

    registerSandboxRoutes(app, options);
    registerMigrationRoutes(app, options);
    registerArtifactRoutes(app, options);

    app.setErrorHandler(async (error, _request, reply) => {
        if (error instanceof FiremigError) {
            await reply
                .code(error.status ?? 500)
                .send(errorEnvelope(error.code, error.message, error.retryable, error.details));
            return;
        }
        if ((error as { validation?: unknown }).validation !== undefined) {
            await reply
                .code(400)
                .send(errorEnvelope(ErrorCode.BadRequest, (error as Error).message));
            return;
        }
        app.log.error(error);
        await reply
            .code(500)
            .send(errorEnvelope(ErrorCode.Internal, "Internal worker error", true));
    });

    return app;
}
