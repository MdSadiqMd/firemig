import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { ErrorCode } from "@firemig/common";
import { nodeFileSystem } from "../src/platform/adapters.js";
import { EpochStore } from "../src/platform/epochs.js";
import { PathModel } from "../src/platform/paths.js";
import { firecrackerLaunchPlan, mountNamespaceSetupPlan } from "../src/planning/planner.js";

const temporaryDirectories: string[] = [];
afterEach(async () =>
    Promise.all(
        temporaryDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })),
    ),
);

describe("epoch persistence", () => {
    it("persists monotonic epochs and rejects stale requests after reload", async () => {
        const directory = await mkdtemp(join(tmpdir(), "firemig-epoch-"));
        temporaryDirectories.push(directory);
        const path = join(directory, "epochs.json");
        const first = new EpochStore(path, nodeFileSystem);
        await first.load();
        expect(await first.accept("sandbox-1", 4)).toEqual({ previous: 0, advanced: true });

        const reloaded = new EpochStore(path, nodeFileSystem);
        await reloaded.load();
        expect(reloaded.get("sandbox-1")).toBe(4);
        await expect(reloaded.accept("sandbox-1", 3)).rejects.toMatchObject({
            code: ErrorCode.Fenced,
        });
    });
});

describe("path model", () => {
    it("uses worker-specific physical paths and worker-independent canonical paths", () => {
        const a = new PathModel("/workers/a").sandbox("sbx-1", 2);
        const b = new PathModel("/workers/b").sandbox("sbx-1", 2);
        expect(a.physicalRootfs).not.toBe(b.physicalRootfs);
        expect(a.canonicalRootfs).toBe(b.canonicalRootfs);
        expect(a.memory).toContain("memory-2.mem");
    });

    it("builds argument-array-only namespace and launch commands", () => {
        const paths = new PathModel("/workers/a").sandbox("sbx-1");
        const plans = [
            ...mountNamespaceSetupPlan(123, paths),
            firecrackerLaunchPlan(123, "fm-sbx1", "/bin/firecracker", paths.apiSocket),
        ];
        expect(plans.every((plan) => plan.file !== "sh" && plan.file !== "bash")).toBe(true);
        expect(plans.at(-1)?.args).toContain("--api-sock");
    });

    it("rejects traversal in identifiers", () => {
        expect(() => new PathModel("/workers/a").sandbox("../escape")).toThrow(
            "Invalid sandbox id",
        );
    });
});
