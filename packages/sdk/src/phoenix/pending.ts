import { ErrorCode } from "@firemig/common";
import { ApiError } from "../errors.js";
import {
    abortError,
    channelError,
    isPhoenixMessage,
    isReplyPayload,
    messageText,
    type PhoenixMessage,
} from "./protocol.js";

interface PendingReply {
    resolve: (response: unknown) => void;
    reject: (error: Error) => void;
    removeAbortListener?: () => void;
}

/** Outstanding Phoenix pushes keyed by ref, with abort wiring and reply resolution. */
export class PendingReplies {
    private readonly entries = new Map<string, PendingReply>();

    add(
        ref: string,
        resolve: (response: unknown) => void,
        reject: (error: Error) => void,
        signal?: AbortSignal,
    ): PendingReply {
        const pending: PendingReply = { resolve, reject };
        if (signal !== undefined) {
            const onAbort = () => {
                if (this.entries.delete(ref)) reject(abortError(signal));
            };
            signal.addEventListener("abort", onAbort, { once: true });
            pending.removeAbortListener = () => signal.removeEventListener("abort", onAbort);
        }
        this.entries.set(ref, pending);
        return pending;
    }

    /** Removes and returns the pending reply for `ref`, detaching its abort listener. */
    take(ref: string): PendingReply | undefined {
        const pending = this.entries.get(ref);
        if (pending === undefined) return undefined;
        this.entries.delete(ref);
        pending.removeAbortListener?.();
        return pending;
    }

    discard(ref: string, pending: PendingReply): void {
        this.entries.delete(ref);
        pending.removeAbortListener?.();
    }

    rejectAll(error: Error): void {
        for (const pending of this.entries.values()) {
            pending.removeAbortListener?.();
            pending.reject(error);
        }
        this.entries.clear();
    }
}

export function settleReply(pending: PendingReply, payload: unknown): void {
    if (!isReplyPayload(payload)) {
        pending.reject(
            new ApiError({
                code: ErrorCode.Internal,
                message: "Invalid Phoenix reply",
                retryable: false,
            }),
        );
        return;
    }
    if (payload.status === "ok") {
        pending.resolve(payload.response);
        return;
    }
    pending.reject(channelError(payload.response));
}

/** Decodes one socket frame and, if it is a reply we are waiting on, settles it. */
export async function dispatchFrame(
    pending: PendingReplies,
    data: unknown,
    onEvent?: (message: PhoenixMessage) => void,
): Promise<void> {
    const text = await messageText(data);
    if (text === undefined) return;

    let message: unknown;
    try {
        message = JSON.parse(text);
    } catch {
        return;
    }
    if (!isPhoenixMessage(message)) return;
    if (message[3] !== "phx_reply" || message[1] === null) {
        onEvent?.(message);
        return;
    }

    const reply = pending.take(message[1]);
    if (reply !== undefined) settleReply(reply, message[4]);
}
