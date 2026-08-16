import type { ObservedCounterEvent } from "./validation/events.js";
import { analyzeSequence } from "./validation/sequence.js";

export type { CounterEvent, ObservedCounterEvent } from "./validation/events.js";
export { parseCounterEvent } from "./validation/events.js";

export interface ValidationInput {
    observations: readonly ObservedCounterEvent[];
    totalMigrationMs: number;
    vmPauseMs: number | undefined;
    bytesTransferred: number;
    reconnectCount: number;
    expectedStart?: number;
    expectedEnd?: number;
    queuedCommandAccepted?: boolean;
    queuedCommandReplayed?: boolean;
}

export interface ValidationReport {
    passed: boolean;
    eventCount: number;
    totalMigrationMs: number;
    vmPauseMs: number | undefined;
    longestEventGapMs: number;
    bytesTransferred: number;
    reconnectCount: number;
    bootIdContinuous: boolean;
    pidContinuous: boolean;
    counterMonotonic: boolean;
    missingSeq: number;
    duplicateSeq: number;
    outOfOrderSeq: number;
    missingNumbers: number[];
    duplicateNumbers: number[];
    observedSequence: number[];
    exactSequence: boolean;
    queuedCommandAccepted: boolean;
    queuedCommandReplayed: boolean;
}

export function validateContinuity(input: ValidationInput): ValidationReport {
    const events = input.observations.map((observation) => observation.event);
    const first = events[0];
    const bootIdContinuous =
        first !== undefined && events.every((event) => event.boot_id === first.boot_id);
    const pidContinuous = first !== undefined && events.every((event) => event.pid === first.pid);
    const counterMonotonic = events.every(
        (event, index) => index === 0 || event.counter >= events[index - 1]!.counter,
    );

    const sequence = analyzeSequence(events, input.expectedStart ?? 1, input.expectedEnd ?? 50);
    const queuedCommandAccepted = input.queuedCommandAccepted ?? true;
    const queuedCommandReplayed = input.queuedCommandReplayed ?? true;

    return {
        passed:
            sequence.exactSequence &&
            bootIdContinuous &&
            pidContinuous &&
            counterMonotonic &&
            input.reconnectCount === 0 &&
            queuedCommandAccepted &&
            queuedCommandReplayed,
        eventCount: events.length,
        totalMigrationMs: input.totalMigrationMs,
        vmPauseMs: input.vmPauseMs,
        longestEventGapMs: longestGapMs(input.observations),
        bytesTransferred: input.bytesTransferred,
        reconnectCount: input.reconnectCount,
        bootIdContinuous,
        pidContinuous,
        counterMonotonic,
        missingSeq: sequence.missingNumbers.length,
        duplicateSeq: sequence.duplicateSeq,
        outOfOrderSeq: sequence.outOfOrderSeq,
        missingNumbers: sequence.missingNumbers,
        duplicateNumbers: sequence.duplicateNumbers,
        observedSequence: sequence.observedSequence,
        exactSequence: sequence.exactSequence,
        queuedCommandAccepted,
        queuedCommandReplayed,
    };
}

function longestGapMs(observations: readonly ObservedCounterEvent[]): number {
    let longest = 0;
    for (let index = 1; index < observations.length; index += 1) {
        longest = Math.max(
            longest,
            observations[index]!.receivedAtMs - observations[index - 1]!.receivedAtMs,
        );
    }
    return longest;
}
