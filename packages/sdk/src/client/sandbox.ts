import type {
    CommandResult,
    ExposePortRequest,
    MigrationInfo,
    PortExposure,
    RunCommandRequest,
    SandboxInfo,
    StartMigrationRequest,
    WriteFileResult,
} from "@firemig/common";
import type { FiremigClient } from "../client.js";
import type { CommandOptions, MutationOptions } from "./options.js";
import { Migration } from "./migration.js";

export class Sandbox {
    readonly files: {
        write: (
            path: string,
            content: string | Uint8Array,
            options?: MutationOptions & { mode?: number },
        ) => Promise<WriteFileResult>;
    };
    readonly commands: {
        run: (request: RunCommandRequest, options?: CommandOptions) => Promise<CommandResult>;
    };
    readonly ports: {
        expose: (request: ExposePortRequest, options?: MutationOptions) => Promise<PortExposure>;
    };

    constructor(
        private readonly client: FiremigClient,
        readonly info: SandboxInfo,
    ) {
        const base = `/v1/sandboxes/${encodeURIComponent(info.id)}`;
        this.files = {
            write: (path, content, options) =>
                this.client.request(`${base}/files`, {
                    method: "PUT",
                    idempotent: true,
                    body: {
                        path,
                        ...(typeof content === "string"
                            ? { content }
                            : { contentBase64: Buffer.from(content).toString("base64") }),
                        ...(options?.mode === undefined ? {} : { mode: options.mode }),
                    },
                    ...(options?.idempotencyKey === undefined
                        ? {}
                        : { idempotencyKey: options.idempotencyKey }),
                    ...(options?.signal === undefined ? {} : { signal: options.signal }),
                }),
        };
        this.commands = {
            run: (request, options) => this.client.runCommand(info.id, request, options),
        };
        this.ports = {
            expose: (request, options) =>
                this.client.request(`${base}/ports`, {
                    method: "POST",
                    body: request,
                    idempotent: true,
                    ...(options ?? {}),
                }),
        };
    }

    async refresh(options?: { signal?: AbortSignal }): Promise<Sandbox> {
        return this.client.sandboxes.get(this.info.id, options);
    }

    async migrate(request: StartMigrationRequest, options?: MutationOptions): Promise<Migration> {
        const info = await this.client.request<MigrationInfo>(
            `/v1/sandboxes/${encodeURIComponent(this.info.id)}/migrations`,
            { method: "POST", body: request, idempotent: true, ...(options ?? {}) },
        );
        return new Migration(this.client, {
            ...info,
            bytesTransferred: info.bytesTransferred ?? 0,
            bytesTotal: info.bytesTotal ?? 0,
        });
    }
}
