import {
    ErrorCode,
    isTerminalPhase,
    type MigrationInfo,
    MigrationPhase,
    type MigrationProgress,
    sleep,
} from "@firemig/common";
import type { FiremigClient } from "../client.js";
import type { WatchOptions } from "./options.js";
import { ApiError, MigrationFailedError } from "../errors.js";
import { parseSse } from "../sse.js";
import { isFailure, parseProgress } from "./migration-progress.js";

const DEFAULT_POLL_INTERVAL_MS = 500;
const DEFAULT_SSE_RECONNECTS = 2;

export class Migration {
    constructor(
        private readonly client: FiremigClient,
        readonly info: MigrationInfo,
    ) {}

    get(options?: { signal?: AbortSignal }): Promise<MigrationInfo> {
        return this.client.request(this.statusPath(), options);
    }

    async *watch(options: WatchOptions = {}): AsyncGenerator<MigrationProgress> {
        let lastEventId: string | undefined;
        let reconnects = 0;
        let retryMs = options.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS;
        const maxReconnects = options.maxSseReconnects ?? DEFAULT_SSE_RECONNECTS;
        const eventsPath = `${this.statusPath()}/events`;
        while (reconnects <= maxReconnects) {
            const stream = await this.openStream(eventsPath, lastEventId, options);
            if (stream === undefined) break;
            for await (const event of parseSse(stream)) {
                if (event.id !== undefined) lastEventId = event.id;
                if (event.retry !== undefined) retryMs = event.retry;
                const progress = parseProgress(event.data, event.id);
                yield progress;
                if (event.event === "error" || isFailure(progress.phase))
                    throw this.migrationError(progress);
                if (event.event === "done" || isTerminalPhase(progress.phase)) return;
            }
            reconnects += 1;
            if (reconnects <= maxReconnects) await sleep(retryMs, options.signal);
        }
        yield* this.poll(options);
    }

    /** Undefined when the endpoint is not a usable event stream, so watch() falls back to polling. */
    private async openStream(
        eventsPath: string,
        lastEventId: string | undefined,
        options: WatchOptions,
    ): Promise<ReadableStream<Uint8Array> | undefined> {
        let response: Response;
        try {
            response = await this.client.raw(eventsPath, {
                accept: "text/event-stream",
                ...(lastEventId === undefined ? {} : { headers: { "last-event-id": lastEventId } }),
                ...(options.signal === undefined ? {} : { signal: options.signal }),
            });
        } catch {
            return undefined;
        }
        const contentType = response.headers.get("content-type") ?? "";
        if (!response.ok || response.body === null || !contentType.includes("text/event-stream"))
            return undefined;
        return response.body;
    }

    private async *poll(options: WatchOptions): AsyncGenerator<MigrationProgress> {
        let signature = "";
        while (true) {
            const status = await this.get(options);
            const progress: MigrationProgress = {
                phase: status.phase,
                bytesTransferred: status.bytesTransferred,
                bytesTotal: status.bytesTotal,
                ts: new Date().toISOString(),
                ...(status.error === undefined ? {} : { error: status.error }),
            };
            const nextSignature = `${progress.phase}:${progress.bytesTransferred}:${progress.bytesTotal}`;
            if (nextSignature !== signature) {
                signature = nextSignature;
                yield progress;
            }
            if (isFailure(status.phase)) throw this.migrationError(progress);
            if (isTerminalPhase(status.phase)) return;
            await sleep(options.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS, options.signal);
        }
    }

    private statusPath(): string {
        const sandbox = encodeURIComponent(this.info.sandboxId);
        return `/v1/sandboxes/${sandbox}/migrations/${encodeURIComponent(this.info.migrationId)}`;
    }

    private migrationError(progress: MigrationProgress): MigrationFailedError {
        return new MigrationFailedError(
            this.info.migrationId,
            progress.error ?? {
                code: ErrorCode.Internal,
                message: `Migration terminated in ${progress.phase}`,
                retryable: false,
            },
        );
    }
}
