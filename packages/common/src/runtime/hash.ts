import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";

export function sha256(data: string | NodeJS.ArrayBufferView): string {
    return createHash("sha256").update(data).digest("hex");
}

export async function sha256File(path: string): Promise<string> {
    const hash = createHash("sha256");
    for await (const chunk of createReadStream(path)) hash.update(chunk as Buffer);
    return hash.digest("hex");
}

export function canonicalJson(value: unknown): string {
    if (value === null) return "null";
    if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
    if (typeof value === "number") return Number.isFinite(value) ? JSON.stringify(value) : "null";
    if (value === undefined) return "null";
    if (typeof value !== "object") throw new TypeError(`Cannot canonicalize ${typeof value}`);
    if (Array.isArray(value)) return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
    if (value instanceof Date) return JSON.stringify(value.toJSON());
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record)
        .filter((key) => {
            const type = typeof record[key];
            return type !== "undefined" && type !== "function" && type !== "symbol";
        })
        .sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(",")}}`;
}

export function requestHash(value: unknown): string {
    return sha256(canonicalJson(value));
}
