import { dirname } from "node:path";
import type { SandboxInfo } from "@firemig/common";
import { ErrorCode, FiremigError, SandboxState } from "@firemig/common";
import type { SpawnedProcess } from "../../platform/adapters.js";
import { FirecrackerClient } from "../../runtime/firecracker.js";
import type { NetworkIdentity } from "../../runtime/network.js";
import {
    firecrackerLaunchPlan,
    mountNamespaceSetupPlan,
    networkCreatePlan,
} from "../../planning/planner.js";
import { VsockGuestClient } from "../../runtime/vsock.js";
import type { WorkerCore } from "../core/worker-core.js";
import { validateMachineSize } from "../core/worker-errors.js";
import { waitForFile, waitForGuest } from "../snapshot/worker-files.js";
import type { CreateWorkerSandboxRequest, SandboxRecord } from "../core/worker-types.js";
import { bootGuest, registerRecord } from "./worker-boot.js";

type AllocatedNetwork = NetworkIdentity & { keys: readonly string[] };

export async function createSandbox(
    core: WorkerCore,
    request: CreateWorkerSandboxRequest,
): Promise<SandboxInfo> {
    if (core.sandboxes.has(request.id))
        throw new FiremigError(
            { code: ErrorCode.BadRequest, message: "Sandbox already exists", retryable: false },
            409,
        );
    validateMachineSize(request.cpu, request.memoryMb);
    await core.epochs.accept(request.id, request.epoch);
    const paths = core.paths.sandbox(request.id);
    await Promise.all([
        core.fs.mkdir(dirname(paths.physicalDirectory), { recursive: true, mode: 0o700 }),
        core.fs.mkdir(dirname(paths.apiSocket), { recursive: true, mode: 0o700 }),
    ]);
    await claimPhysicalDirectory(core, request.id, paths.physicalDirectory);

    let network: AllocatedNetwork;
    try {
        network = core.allocator.allocateNetwork(request);
    } catch (error) {
        await core.fs.rm(paths.physicalDirectory, { recursive: true, force: true });
        throw error;
    }

    let mountNamespace: SpawnedProcess | undefined;
    let launched = false;
    try {
        if ((request.mode ?? "boot") === "boot") {
            await core.lifecycle.copySparse(
                request.rootfsPath ?? request.rootfs ?? core.configuration.baseRootfsPath,
                paths.physicalRootfs,
            );
        }
        mountNamespace = core.lifecycle.startMountNamespace();
        await core.lifecycle.runPlans(
            networkCreatePlan({
                sandboxId: request.id,
                netns: network.netns,
                hostVeth: network.hostVeth,
                hostAddress: network.hostAddress,
                namespaceAddress: network.namespaceAddress,
                ...(request.mtu === undefined ? {} : { mtu: request.mtu }),
            }),
        );
        await core.lifecycle.runPlans(mountNamespaceSetupPlan(mountNamespace.pid, paths));
        const firecracker = core.lifecycle.launch(
            request.id,
            mountNamespace,
            firecrackerLaunchPlan(
                mountNamespace.pid,
                network.netns,
                core.configuration.firecrackerBinary,
                paths.apiSocket,
            ),
        );
        launched = true;
        await waitForFile(core.fs, paths.apiSocket, 5_000, firecracker);

        const record = registerRecord(core, request, paths, network);
        if ((request.mode ?? "boot") === "boot") await bootGuest(core, request, record);
        return record.info;
    } catch (error) {
        if (launched) await core.lifecycle.stop(request.id);
        else mountNamespace?.kill("SIGKILL");
        await core.runCleanupPlans(network.netns, network.hostVeth);
        core.allocator.releaseNetwork(request.id, network.keys);
        await core.fs.rm(paths.physicalDirectory, { recursive: true, force: true });
        core.sandboxes.delete(request.id);
        throw error;
    }
}

async function claimPhysicalDirectory(
    core: WorkerCore,
    id: string,
    physicalPath: string,
): Promise<void> {
    try {
        await core.fs.mkdir(physicalPath, { mode: 0o700 });
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
        throw new FiremigError(
            {
                code: ErrorCode.BadRequest,
                message:
                    "Canonical sandbox path is occupied; quarantine or remove the stale generation first",
                retryable: false,
                details: { sandboxId: id, physicalPath },
            },
            409,
        );
    }
}
