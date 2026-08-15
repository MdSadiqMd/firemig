#!/usr/bin/env node
import { nodeFileSystem, nodeOsAdapter, nodeProcessAdapter } from "./platform/adapters.js";
import { parsePeerUrls, parsePortBase } from "./platform/config.js";
import { buildAgentServer } from "./server/server.js";
import { WorkerService } from "./worker/index.js";

function required(name: string): string {
    const value = process.env[name];
    if (value === undefined || value === "") throw new Error(`${name} is required`);
    return value;
}

const agentToken = process.env.FIREMIG_AGENT_TOKEN;
const peerAuthToken = process.env.FIREMIG_PEER_AUTH_TOKEN ?? agentToken;
const firecrackerBinary = required("FIRECRACKER_BINARY");
const kernelPath = required("FIREMIG_KERNEL");
const baseRootfsPath = required("FIREMIG_ROOTFS");

for (const dependency of [firecrackerBinary, kernelPath, baseRootfsPath]) {
    const stat = await nodeFileSystem.stat(dependency);
    if (!stat.isFile()) throw new Error(`Required worker dependency is not a file: ${dependency}`);
}

const worker = new WorkerService(
    {
        workerId: required("FIREMIG_WORKER_ID"),
        region: process.env.FIREMIG_REGION ?? required("FIREMIG_WORKER_ID"),
        workerRoot: required("FIREMIG_WORKDIR"),
        firecrackerBinary,
        kernelPath,
        baseRootfsPath,
        proxyHost: process.env.FIREMIG_PROXY_HOST ?? "127.0.0.1",
        portBase: parsePortBase(process.env.FIREMIG_PORT_BASE),
        peerUrls: parsePeerUrls(process.env.FIREMIG_PEER_URLS),
        ...(process.env.FIREMIG_SHARED_WORKER_ROOT === undefined
            ? {}
            : {
                  sharedWorkerRoot: process.env.FIREMIG_SHARED_WORKER_ROOT,
              }),
        ...(peerAuthToken === undefined ? {} : { peerAuthToken }),
        hostCompatibility: {
            firecrackerVersion: required("FIRECRACKER_VERSION"),
            firecrackerDigest: required("FIRECRACKER_SHA256"),
            snapshotFormatVersion: required("FIRECRACKER_SNAPSHOT_FORMAT"),
            hostKernelVersion: nodeOsAdapter.release(),
            architecture: nodeOsAdapter.arch(),
            cpuVendor: required("FIREMIG_CPU_VENDOR"),
            cpuModel: required("FIREMIG_CPU_MODEL"),
            cpuFamily: required("FIREMIG_CPU_FAMILY"),
            cpuStepping: required("FIREMIG_CPU_STEPPING"),
            guestKernelDigest: required("FIREMIG_KERNEL_SHA256"),
            cpuTemplate: process.env.FIREMIG_CPU_TEMPLATE ?? "None",
            smt: false,
            hugePages: "None",
        },
    },
    nodeFileSystem,
    nodeProcessAdapter,
);

await worker.initialize();
const server = buildAgentServer({
    worker,
    fs: nodeFileSystem,
    ...(agentToken === undefined ? {} : { authToken: agentToken }),
});
await server.listen({
    host: process.env.FIREMIG_AGENT_HOST ?? "127.0.0.1",
    port: Number(process.env.FIREMIG_AGENT_PORT ?? "4101"),
});
