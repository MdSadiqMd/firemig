import { SandboxState } from "@firemig/common";
import { FirecrackerClient } from "../../runtime/firecracker.js";
import type { NetworkIdentity } from "../../runtime/network.js";
import { VsockGuestClient } from "../../runtime/vsock.js";
import type { WorkerCore } from "../core/worker-core.js";
import { waitForGuest } from "../snapshot/worker-files.js";
import type { CreateWorkerSandboxRequest, SandboxRecord } from "../core/worker-types.js";

type AllocatedNetwork = NetworkIdentity & { keys: readonly string[] };

export function registerRecord(
    core: WorkerCore,
    request: CreateWorkerSandboxRequest,
    paths: SandboxRecord["paths"],
    network: AllocatedNetwork,
): SandboxRecord {
    const firecracker =
        core.firecrackerTransport === undefined
            ? new FirecrackerClient(paths.apiSocket)
            : new FirecrackerClient(paths.apiSocket, core.firecrackerTransport);
    const guest =
        core.vsockConnector === undefined
            ? new VsockGuestClient(paths.physicalVsock)
            : new VsockGuestClient(paths.physicalVsock, 5000, core.vsockConnector);
    const record: SandboxRecord = {
        info: {
            id: request.id,
            region: core.configuration.region,
            worker: core.configuration.workerId,
            state: SandboxState.Booting,
            epoch: request.epoch,
            cpu: request.cpu,
            memoryMb: request.memoryMb,
            createdAt: new Date().toISOString(),
            ports: [],
        },
        paths,
        netns: network.netns,
        hostVeth: network.hostVeth,
        namespaceAddress: network.namespaceAddress,
        guest,
        firecracker,
        generation: 0,
        artifacts: {},
        networkKeys: network.keys,
    };
    core.sandboxes.set(request.id, record);
    return record;
}

export async function bootGuest(
    core: WorkerCore,
    request: CreateWorkerSandboxRequest,
    record: SandboxRecord,
): Promise<void> {
    const { cpuTemplate } = core.configuration.hostCompatibility;
    await record.firecracker.configure({
        kernelPath: request.kernelPath ?? request.kernel ?? core.configuration.kernelPath,
        rootfsPath: record.paths.canonicalRootfs,
        vsockPath: record.paths.canonicalVsock,
        vcpuCount: request.cpu,
        memSizeMib: request.memoryMb,
        ...(cpuTemplate === "None" ? {} : { cpuTemplate }),
        ...(request.mtu === undefined ? {} : { mtu: request.mtu }),
    });
    await record.firecracker.start();
    const ready = await waitForGuest(record.guest, 30_000);
    record.info = {
        ...record.info,
        state: SandboxState.Running,
        bootId: ready.bootId,
        bootedAt: new Date().toISOString(),
    };
}
