export interface CounterEvent {
    seq: number;
    boot_id: string;
    pid: number;
    counter: number;
    time: string;
}

export interface ObservedCounterEvent {
    event: CounterEvent;
    receivedAtMs: number;
}

export function parseCounterEvent(line: string): CounterEvent {
    const value = JSON.parse(line) as Partial<CounterEvent>;
    if (
        !Number.isSafeInteger(value.seq) ||
        typeof value.boot_id !== "string" ||
        value.boot_id === "" ||
        !Number.isSafeInteger(value.pid) ||
        !Number.isSafeInteger(value.counter) ||
        typeof value.time !== "string"
    ) {
        throw new Error("Invalid counter event");
    }
    return value as CounterEvent;
}
