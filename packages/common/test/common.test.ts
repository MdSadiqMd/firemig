import { describe, expect, it, vi } from "vitest";
import { backoffDelay, canonicalJson, parseFaults, requestHash, sleep } from "../src/index.js";

describe("fault parser", () => {
    it("parses flags, strings, and numeric values", () => {
        const faults = parseFaults("dest_unreachable, transfer_abort_after=4096,force_path=IDLE");
        expect(faults.enabled("dest_unreachable")).toBe(true);
        expect(faults.number("transfer_abort_after")).toBe(4096);
        expect(faults.string("force_path")).toBe("IDLE");
    });

    it("rejects malformed and duplicate faults", () => {
        expect(() => parseFaults("bad-name")).toThrow("Invalid fault name");
        expect(() => parseFaults("x,x")).toThrow("Duplicate fault");
        expect(() => parseFaults("x=")).toThrow("requires a value");
    });
});

describe("hashing and backoff", () => {
    it("canonicalizes object key order", () => {
        expect(canonicalJson({ b: 2, a: { d: 4, c: 3 } })).toBe('{"a":{"c":3,"d":4},"b":2}');
        expect(canonicalJson({ absent: undefined, values: [1, undefined] })).toBe(
            '{"values":[1,null]}',
        );
        expect(requestHash({ a: 1, b: 2 })).toBe(requestHash({ b: 2, a: 1 }));
    });

    it("caps deterministic backoff", () => {
        expect(
            backoffDelay(10, { initialMs: 10, maximumMs: 100, jitter: 0, random: () => 0 }),
        ).toBe(100);
    });

    it("removes abort listeners after a completed sleep", async () => {
        const delay = new AbortController();
        const timeout = vi.spyOn(AbortSignal, "timeout").mockReturnValue(delay.signal);
        try {
            const controller = new AbortController();
            const removeListener = vi.spyOn(controller.signal, "removeEventListener");
            const completed = sleep(10, controller.signal);

            delay.abort();
            await completed;

            expect(removeListener).toHaveBeenCalledWith("abort", expect.any(Function));
        } finally {
            timeout.mockRestore();
        }
    });
});
