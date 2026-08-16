import type {
    CommandResult,
    CreateSandboxRequest,
    RunCommandRequest,
    SandboxInfo,
} from "@firemig/common";
import type {
    CommandOptions,
    Fetch,
    FiremigClientOptions,
    MutationOptions,
    RequestOptions,
} from "./client/options.js";
import { type RequestContext, sendRequest } from "./client/request.js";
import { Sandbox } from "./client/sandbox.js";
import { PhoenixCommandTransport } from "./websocket.js";

export * from "./client/options.js";
export { Migration } from "./client/migration.js";
export { Sandbox } from "./client/sandbox.js";

export class FiremigClient {
    readonly sandboxes: {
        create: (request: CreateSandboxRequest, options?: MutationOptions) => Promise<Sandbox>;
        get: (id: string, options?: { signal?: AbortSignal }) => Promise<Sandbox>;
    };
    private readonly baseUrl: string;
    private readonly fetcher: Fetch;
    private readonly maxRetries: number;
    private readonly commandTransport: PhoenixCommandTransport;

    constructor(private readonly options: FiremigClientOptions) {
        this.baseUrl = options.baseUrl.replace(/\/$/, "");
        this.fetcher = options.fetch ?? globalThis.fetch;
        this.maxRetries = options.maxRetries ?? 3;
        this.commandTransport = new PhoenixCommandTransport(
            this.baseUrl,
            options.userId,
            options.token,
            options.webSocketFactory,
        );
        this.sandboxes = {
            create: async (request, mutationOptions) => {
                const info = await this.request<SandboxInfo>("/v1/sandboxes", {
                    method: "POST",
                    body: request,
                    idempotent: true,
                    ...(mutationOptions ?? {}),
                });
                return new Sandbox(this, info);
            },
            get: async (id, getOptions) => {
                const info = await this.request<SandboxInfo>(
                    `/v1/sandboxes/${encodeURIComponent(id)}`,
                    getOptions,
                );
                return new Sandbox(this, info);
            },
        };
    }

    close(): void {
        this.commandTransport.close();
    }

    runCommand(
        sandboxId: string,
        request: RunCommandRequest,
        options?: CommandOptions,
    ): Promise<CommandResult> {
        return this.commandTransport.runCommand(
            sandboxId,
            request,
            options?.idempotencyKey ?? globalThis.crypto.randomUUID(),
            options?.signal,
            options?.awaitCompletion ?? false,
        );
    }

    request<T>(path: string, options: RequestOptions = {}): Promise<T> {
        return sendRequest<T>(this.context(), path, options);
    }

    raw(path: string, options: RequestOptions): Promise<Response> {
        return this.fetcher(`${this.baseUrl}${path}`, {
            method: options.method ?? "GET",
            headers: this.buildHeaders(options),
            ...(options.signal === undefined ? {} : { signal: options.signal }),
        });
    }

    private context(): RequestContext {
        return {
            baseUrl: this.baseUrl,
            fetcher: this.fetcher,
            maxRetries: this.maxRetries,
            headers: (options, idempotencyKey) => this.buildHeaders(options, idempotencyKey),
        };
    }

    private buildHeaders(options: RequestOptions, idempotencyKey?: string): Record<string, string> {
        return {
            accept: options.accept ?? "application/json",
            ...(this.options.token === undefined
                ? {}
                : { authorization: `Bearer ${this.options.token}` }),
            ...(idempotencyKey === undefined ? {} : { "idempotency-key": idempotencyKey }),
            ...(options.headers ?? {}),
        };
    }
}
