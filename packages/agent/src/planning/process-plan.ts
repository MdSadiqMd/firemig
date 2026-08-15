import type { CommandPlan } from "./command-plan.js";
import { assertIdentifier, type SandboxPaths } from "../platform/paths.js";

export function mountNamespaceSetupPlan(namespacePid: number, paths: SandboxPaths): CommandPlan[] {
    if (!Number.isSafeInteger(namespacePid) || namespacePid <= 0)
        throw new Error("Invalid mount namespace PID");
    const prefix = [`--mount=/proc/${namespacePid}/ns/mnt`, "--"];
    return [
        { file: "nsenter", args: [...prefix, "mkdir", "-p", paths.canonicalDirectory] },
        {
            file: "nsenter",
            args: [...prefix, "mount", "--bind", paths.physicalDirectory, paths.canonicalDirectory],
        },
    ];
}

export function firecrackerLaunchPlan(
    namespacePid: number,
    netns: string,
    firecrackerBinary: string,
    apiSocket: string,
): CommandPlan {
    assertIdentifier(netns, "network namespace");
    return {
        file: "nsenter",
        args: [
            `--mount=/proc/${namespacePid}/ns/mnt`,
            `--net=/var/run/netns/${netns}`,
            "--",
            firecrackerBinary,
            "--api-sock",
            apiSocket,
        ],
    };
}
