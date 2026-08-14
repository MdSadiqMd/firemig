export type FaultValue = true | string | number;

export class Faults {
    readonly values: ReadonlyMap<string, FaultValue>;

    constructor(values: ReadonlyMap<string, FaultValue> = new Map()) {
        this.values = values;
    }

    enabled(name: string): boolean {
        return this.values.has(name);
    }

    value(name: string): FaultValue | undefined {
        return this.values.get(name);
    }

    string(name: string): string | undefined {
        const value = this.value(name);
        return typeof value === "string" ? value : undefined;
    }

    number(name: string): number | undefined {
        const value = this.value(name);
        return typeof value === "number" ? value : undefined;
    }
}

const faultName = /^[a-z][a-z0-9_]*$/;

export function parseFaults(input: string | undefined): Faults {
    const values = new Map<string, FaultValue>();
    if (input === undefined || input.trim() === "") return new Faults(values);

    for (const rawPart of input.split(",")) {
        const part = rawPart.trim();
        if (part === "") continue;
        const equals = part.indexOf("=");
        const name = (equals < 0 ? part : part.slice(0, equals)).trim();
        if (!faultName.test(name)) throw new Error(`Invalid fault name: ${name}`);
        if (values.has(name)) throw new Error(`Duplicate fault: ${name}`);
        if (equals < 0) {
            values.set(name, true);
            continue;
        }
        const rawValue = part.slice(equals + 1).trim();
        if (rawValue === "") throw new Error(`Fault ${name} requires a value`);
        const numeric = Number(rawValue);
        values.set(
            name,
            Number.isFinite(numeric) && /^-?\d+(?:\.\d+)?$/.test(rawValue) ? numeric : rawValue,
        );
    }
    return new Faults(values);
}
