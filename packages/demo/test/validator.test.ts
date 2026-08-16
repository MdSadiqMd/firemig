import { describe, expect, it } from "vitest";
import {
    parseCounterEvent,
    validateContinuity,
    type ObservedCounterEvent,
} from "../src/validator.js";

function observation(
    seq: number,
    receivedAtMs: number,
    overrides: Partial<{ boot_id: string; pid: number; counter: number }> = {},
): ObservedCounterEvent {
    return {
        receivedAtMs,
        event: {
            seq,
            boot_id: overrides.boot_id ?? "boot-1",
            pid: overrides.pid ?? 42,
            counter: overrides.counter ?? seq,
            time: "2026-08-14T00:00:00Z",
        },
    };
}

describe("continuity validator", () => {
    it("passes only an exact one-to-fifty sequence", () => {
        const report = validateContinuity({
            observations: Array.from({ length: 50 }, (_value, index) =>
                observation(index + 1, index * 250),
            ),
            totalMigrationMs: 3210,
            vmPauseMs: 2200,
            bytesTransferred: 8192,
            reconnectCount: 0,
        });
        expect(report).toMatchObject({
            passed: true,
            exactSequence: true,
            missingSeq: 0,
            duplicateSeq: 0,
            outOfOrderSeq: 0,
            observedSequence: Array.from({ length: 50 }, (_value, index) => index + 1),
        });
    });

    it("reports sequence loss, duplicates, and ordering failures", () => {
        const report = validateContinuity({
            observations: [
                observation(1, 1_000),
                observation(2, 2_000),
                observation(2, 2_100),
                observation(5, 6_000),
            ],
            totalMigrationMs: 3210,
            vmPauseMs: 2200,
            bytesTransferred: 8192,
            reconnectCount: 0,
        });
        expect(report).toMatchObject({
            passed: false,
            exactSequence: false,
            bootIdContinuous: true,
            pidContinuous: true,
            counterMonotonic: true,
            missingSeq: 47,
            duplicateSeq: 1,
            outOfOrderSeq: 2,
            duplicateNumbers: [2],
            longestEventGapMs: 3900,
            bytesTransferred: 8192,
            reconnectCount: 0,
        });
    });

    it("fails on reboot, process restart, counter rollback, or reconnect", () => {
        const report = validateContinuity({
            observations: [
                observation(1, 0, { counter: 10 }),
                observation(2, 1_000, { boot_id: "boot-2", pid: 99, counter: 1 }),
            ],
            totalMigrationMs: 1000,
            vmPauseMs: undefined,
            bytesTransferred: 100,
            reconnectCount: 1,
        });
        expect(report).toMatchObject({
            passed: false,
            bootIdContinuous: false,
            pidContinuous: false,
            counterMonotonic: false,
        });
    });

    it("rejects malformed server events", () => {
        expect(() => parseCounterEvent('{"seq":1}')).toThrow("Invalid counter event");
    });
});
