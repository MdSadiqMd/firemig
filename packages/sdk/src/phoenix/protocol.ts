import { ErrorCode, type ErrorBody, isErrorEnvelope } from "@firemig/common";
import { ApiError, FencedError, IdempotencyConflictError } from "../errors.js";

export interface WebSocketEvent {
    data?: unknown;
    code?: number;
    reason?: string;
}

export interface WebSocketLike {
    readonly readyState: number;
    send(data: string): void;
    close(code?: number, reason?: string): void;
    addEventListener(type: string, listener: (event: WebSocketEvent) => void): void;
}

export type WebSocketFactory = (url: string) => WebSocketLike;

export type PhoenixMessage = [
    joinRef: string | null,
    ref: string | null,
    topic: string,
    event: string,
    payload: unknown,
];

export const OPEN = 1;
export const HEARTBEAT_INTERVAL_MS = 30_000;

export function defaultWebSocketFactory(url: string): WebSocketLike {
    const WebSocketConstructor = (
        globalThis as {
            WebSocket?: new (url: string) => WebSocketLike;
        }
    ).WebSocket;
    if (WebSocketConstructor === undefined) {
        throw new Error("WebSocket is unavailable; provide FiremigClientOptions.webSocketFactory");
    }
    return new WebSocketConstructor(url);
}

export function isPhoenixMessage(value: unknown): value is PhoenixMessage {
    return (
        Array.isArray(value) &&
        value.length === 5 &&
        (typeof value[0] === "string" || value[0] === null) &&
        (typeof value[1] === "string" || value[1] === null) &&
        typeof value[2] === "string" &&
        typeof value[3] === "string"
    );
}

export function isReplyPayload(value: unknown): value is { status: string; response: unknown } {
    return (
        typeof value === "object" &&
        value !== null &&
        typeof (value as { status?: unknown }).status === "string" &&
        "response" in value
    );
}

export function channelError(value: unknown): ApiError {
    const body = errorBody(value);
    if (body.code === ErrorCode.Fenced) return new FencedError(body);
    if (body.code === ErrorCode.IdempotencyKeyConflict) return new IdempotencyConflictError(body);
    return new ApiError(body);
}

export async function messageText(data: unknown): Promise<string | undefined> {
    if (typeof data === "string") return data;
    if (data instanceof ArrayBuffer) return new TextDecoder().decode(data);
    if (ArrayBuffer.isView(data)) return new TextDecoder().decode(data);
    if (typeof Blob !== "undefined" && data instanceof Blob) return await data.text();
    return undefined;
}

export function abortError(signal: AbortSignal): Error {
    return signal.reason instanceof Error ? signal.reason : new Error("The operation was aborted");
}

function errorBody(value: unknown): ErrorBody {
    if (isErrorEnvelope(value)) return value.error;
    if (isErrorBody(value)) return value;
    const message =
        typeof value === "object" &&
        value !== null &&
        typeof (value as { reason?: unknown }).reason === "string"
            ? (value as { reason: string }).reason
            : "Phoenix channel request failed";
    return { code: ErrorCode.Internal, message, retryable: false };
}

function isErrorBody(value: unknown): value is ErrorBody {
    return (
        typeof value === "object" &&
        value !== null &&
        typeof (value as { code?: unknown }).code === "string" &&
        typeof (value as { message?: unknown }).message === "string" &&
        typeof (value as { retryable?: unknown }).retryable === "boolean"
    );
}
