import type { WebSocketFactory } from "../websocket.js";

export type Fetch = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export interface FiremigClientOptions {
    baseUrl: string;
    userId: string;
    token?: string;
    fetch?: Fetch;
    webSocketFactory?: WebSocketFactory;
    maxRetries?: number;
}

export interface MutationOptions {
    idempotencyKey?: string;
    signal?: AbortSignal;
}

export interface CommandOptions extends MutationOptions {
    awaitCompletion?: boolean;
}

export interface WatchOptions {
    signal?: AbortSignal;
    pollIntervalMs?: number;
    maxSseReconnects?: number;
}

export interface RequestOptions extends MutationOptions {
    method?: "GET" | "POST" | "PUT";
    body?: unknown;
    idempotent?: boolean;
    accept?: string;
    headers?: Record<string, string>;
}
