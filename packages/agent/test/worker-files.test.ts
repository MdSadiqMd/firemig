import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { nodeFileSystem, type SpawnedProcess } from "../src/platform/adapters.js";
import { waitForFile } from "../src/worker/snapshot/worker-files.js";

const temporaryDirectories: string[] = [];

afterEach(async () =>
    Promise.all(
        temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })),
    ),
);

describe("file readiness", () => {
    it("resolves from a filesystem notification when the socket appears", async () => {
        const directory = await mkdtemp(join(tmpdir(), "firemig-watch-"));
        temporaryDirectories.push(directory);
        const socketPath = join(directory, "firecracker.socket");
        const readiness = waitForFile(nodeFileSystem, socketPath, 1_000);

        await writeFile(socketPath, "");

        await expect(readiness).resolves.toBeUndefined();
    });

    it("rejects immediately when Firecracker exits before creating its socket", async () => {
        const directory = await mkdtemp(join(tmpdir(), "firemig-watch-"));
        temporaryDirectories.push(directory);
        const process: SpawnedProcess = {
            pid: 42,
            exited: Promise.resolve({ code: 1, signal: null }),
            kill: () => true,
        };

        await expect(
            waitForFile(nodeFileSystem, join(directory, "missing.socket"), 10_000, process),
        ).rejects.toThrow("Process exited before creating");
    });
});
