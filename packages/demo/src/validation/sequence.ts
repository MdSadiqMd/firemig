import type { CounterEvent } from "./events.js";

export interface SequenceAnalysis {
    missingNumbers: number[];
    duplicateNumbers: number[];
    observedSequence: number[];
    duplicateSeq: number;
    outOfOrderSeq: number;
    exactSequence: boolean;
}

/**
 * Compares the sequence numbers actually observed against the contiguous range
 * the server was expected to emit, so a delivery gap can be reported separately
 * from a broken connection.
 */
export function analyzeSequence(
    events: readonly CounterEvent[],
    expectedStart: number,
    expectedEnd: number,
): SequenceAnalysis {
    const seen = new Set<number>();
    const duplicateNumbers: number[] = [];
    for (const event of events) {
        if (seen.has(event.seq)) duplicateNumbers.push(event.seq);
        seen.add(event.seq);
    }

    const expected = Array.from(
        { length: expectedEnd - expectedStart + 1 },
        (_value, index) => expectedStart + index,
    );
    const observedSequence = events.map((event) => event.seq);

    let outOfOrderSeq = 0;
    for (let index = 1; index < observedSequence.length; index += 1) {
        if (observedSequence[index] !== observedSequence[index - 1]! + 1) outOfOrderSeq += 1;
    }

    return {
        missingNumbers: expected.filter((value) => !seen.has(value)),
        duplicateNumbers,
        observedSequence,
        duplicateSeq: duplicateNumbers.length,
        outOfOrderSeq,
        exactSequence:
            observedSequence.length === expected.length &&
            observedSequence.every((value, index) => value === expected[index]),
    };
}
