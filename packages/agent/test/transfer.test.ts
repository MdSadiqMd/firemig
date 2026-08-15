import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { ErrorCode, type ArtifactDescriptor } from "@firemig/common";
import { nodeFileSystem } from "../src/platform/adapters.js";
import {
    parseRangeHeader,
    pullArtifact,
    runAbortableOperations,
    type ArtifactHttpClient,
} from "../src/artifacts/transfer.js";

const temporaryDirectories: string[] = [];
afterEach(async () =>
    Promise.all(
        temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })),
    ),
);

function descriptor(content: Buffer): ArtifactDescriptor {
    return {
        kind: "mem",
        name: "memory.mem",
        size: content.length,
        sha256: createHash("sha256").update(content).digest("hex"),
    };
}

describe("artifact transfer", () => {
    it("resumes a partial file, verifies SHA-256, fsyncs, and renames", async () => {
        const directory = await mkdtemp(join(tmpdir(), "firemig-transfer-"));
        temporaryDirectories.push(directory);
        const destination = join(directory, "memory.mem");
        const content = Buffer.from("hello world");
        await writeFile(`${destination}.partial`, content.subarray(0, 5));
        let range: string | null = null;
        const http: ArtifactHttpClient = async (_url, init) => {
            range = new Headers(init.headers).get("range");
            return {
                status: 206,
                headers: new Headers({ "x-artifact-sha256": descriptor(content).sha256 }),
                body: (async function* () {
                    yield content.subarray(5);
                })(),
            };
        };
        const result = await pullArtifact({
            url: "http://source/artifact",
            destinationPath: destination,
            descriptor: descriptor(content),
            fs: nodeFileSystem,
            http,
        });
        expect(range).toBe("bytes=5-");
        expect(result).toEqual({ resumedAt: 5, bytesWritten: 6 });
        expect(await readFile(destination)).toEqual(content);
        await expect(stat(`${destination}.partial`)).rejects.toMatchObject({ code: "ENOENT" });
    });

    it("rejects and removes a corrupt completed partial", async () => {
        const directory = await mkdtemp(join(tmpdir(), "firemig-transfer-"));
        temporaryDirectories.push(directory);
        const destination = join(directory, "memory.mem");
        const content = Buffer.from("correct");
        await writeFile(`${destination}.partial`, Buffer.from("corrupt"));
        await expect(
            pullArtifact({
                url: "http://source/artifact",
                destinationPath: destination,
                descriptor: descriptor(content),
                fs: nodeFileSystem,
                http: async () => {
                    throw new Error("should not fetch");
                },
            }),
        ).rejects.toMatchObject({ code: ErrorCode.ArtifactHashMismatch });
        await expect(stat(`${destination}.partial`)).rejects.toMatchObject({ code: "ENOENT" });
    });

    it("parses bounded byte ranges", () => {
        expect(parseRangeHeader("bytes=10-20", 100)).toEqual({ start: 10, end: 20 });
        expect(parseRangeHeader("bytes=90-", 100)).toEqual({ start: 90, end: 99 });
        expect(() => parseRangeHeader("bytes=100-", 100)).toThrow();
    });

    it("aborts and settles sibling operations before reporting a failure", async () => {
        let siblingSettled = false;
        const failure = new Error("transfer failed");

        const operations = runAbortableOperations([
            async () => {
                throw failure;
            },
            async (signal) => {
                await new Promise<void>((resolve) => {
                    signal.addEventListener("abort", () => resolve(), { once: true });
                });
                siblingSettled = true;
            },
        ]);

        await expect(operations).rejects.toBe(failure);
        expect(siblingSettled).toBe(true);
    });
});
