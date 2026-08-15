import type {
    CommandResult,
    PortExposure,
    RunCommandRequest,
    WriteFileRequest,
    WriteFileResult,
} from "@firemig/common";
import { sha256 } from "@firemig/common";
import { addressWithoutPrefix } from "../../runtime/network.js";
import { exposePortPlan } from "../../planning/planner.js";
import type { WorkerCore } from "../core/worker-core.js";
import { workerBadRequest } from "../core/worker-errors.js";

export async function runGuestCommand(
    core: WorkerCore,
    id: string,
    epoch: number,
    request: RunCommandRequest,
): Promise<CommandResult> {
    const record = await core.mutableRecord(id, epoch);
    const result = await record.guest.runCommand({
        command: request.command,
        background: request.background ?? false,
        ...(request.cwd === undefined ? {} : { cwd: request.cwd }),
        ...(request.env === undefined ? {} : { env: request.env }),
        ...(request.timeoutMs === undefined ? {} : { timeoutMs: request.timeoutMs }),
    });
    return result as unknown as CommandResult;
}

export async function writeGuestFile(
    core: WorkerCore,
    id: string,
    epoch: number,
    request: WriteFileRequest,
): Promise<WriteFileResult> {
    const record = await core.mutableRecord(id, epoch);
    if ((request.content === undefined) === (request.contentBase64 === undefined))
        throw workerBadRequest("Specify exactly one of content or contentBase64");

    const content =
        request.content === undefined
            ? Buffer.from(request.contentBase64 as string, "base64")
            : Buffer.from(request.content);
    const result = await record.guest.writeFile({
        path: request.path,
        contentBase64: content.toString("base64"),
        ...(request.mode === undefined ? {} : { mode: request.mode }),
    });
    return {
        path: request.path,
        bytes: content.length,
        sha256: sha256(content),
        ...result,
    } as WriteFileResult;
}

export async function exposeGuestPort(
    core: WorkerCore,
    id: string,
    epoch: number,
    guestPort: number,
): Promise<PortExposure> {
    const record = await core.mutableRecord(id, epoch);
    const existing = record.info.ports?.find((port) => port.guestPort === guestPort);
    if (existing !== undefined) return existing;

    await core.lifecycle.runPlans(exposePortPlan(record.netns, record.namespaceAddress, guestPort));
    const proxyPort = core.allocator.allocatePort(id, guestPort);
    try {
        await core.relays.start(
            id,
            guestPort,
            proxyPort,
            addressWithoutPrefix(record.namespaceAddress),
        );
    } catch (error) {
        core.allocator.releasePort(proxyPort);
        throw error;
    }
    const exposure: PortExposure = {
        guestPort,
        proxyHost: core.configuration.proxyHost,
        proxyPort,
        url: `tcp://${core.configuration.proxyHost}:${proxyPort}`,
    };
    record.info.ports = [...(record.info.ports ?? []), exposure];
    return exposure;
}
