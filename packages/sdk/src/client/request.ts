import { backoffDelay, sleep } from "@firemig/common";
import type { Fetch, RequestOptions } from "./options.js";
import { errorFromResponse } from "../errors.js";

export interface RequestContext {
    baseUrl: string;
    fetcher: Fetch;
    maxRetries: number;
    headers: (options: RequestOptions, idempotencyKey?: string) => Record<string, string>;
}

export async function sendRequest<T>(
    context: RequestContext,
    path: string,
    options: RequestOptions,
): Promise<T> {
    const method = options.method ?? "GET";
    const mutating = method !== "GET";
    const idempotencyKey =
        mutating && options.idempotent === true
            ? (options.idempotencyKey ?? globalThis.crypto.randomUUID())
            : options.idempotencyKey;
    const headers = context.headers(options, idempotencyKey);
    let body: string | undefined;
    if (options.body !== undefined) {
        body = JSON.stringify(options.body);
        headers["content-type"] = "application/json";
    }
    // A mutation without an idempotency key is never retried: the coordinator cannot tell
    // a retry from a second request, so at-most-once is the only safe choice.
    const retryable = !mutating || idempotencyKey !== undefined;

    for (let attempt = 0; ; attempt += 1) {
        let response: Response;
        try {
            response = await context.fetcher(`${context.baseUrl}${path}`, {
                method,
                headers,
                ...(body === undefined ? {} : { body }),
                ...(options.signal === undefined ? {} : { signal: options.signal }),
            });
        } catch (error) {
            if (attempt >= context.maxRetries || !retryable || options.signal?.aborted === true)
                throw error;
            await sleep(backoffDelay(attempt), options.signal);
            continue;
        }
        if (response.ok) {
            if (response.status === 204) return undefined as T;
            return (await response.json()) as T;
        }
        const apiError = await errorFromResponse(response);
        if (!apiError.retryable || attempt >= context.maxRetries || !retryable) throw apiError;
        await sleep(backoffDelay(attempt), options.signal);
    }
}
