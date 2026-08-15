import { describe, expect, it, vi } from "vitest";
import {
    FirecrackerClient,
    type UnixHttpRequest,
    type UnixHttpTransport,
} from "../src/runtime/firecracker.js";

describe("FirecrackerClient", () => {
    it("constructs boot requests against the Unix socket", async () => {
        const requests: UnixHttpRequest[] = [];
        const transport: UnixHttpTransport = vi.fn(async (request) => {
            requests.push(request);
            return { statusCode: 204, headers: {}, body: "" };
        });
        const client = new FirecrackerClient("/worker/a.socket", transport);
        await client.configure({
            kernelPath: "/assets/vmlinux",
            rootfsPath: "/var/lib/firemig/sandboxes/s1/rootfs.ext4",
            vsockPath: "/var/lib/firemig/sandboxes/s1/vsock.socket",
            vcpuCount: 2,
            memSizeMib: 1024,
            cpuTemplate: "T2S",
            mtu: 1400,
        });
        await client.start();

        expect(requests.map(({ method, path }) => [method, path])).toEqual([
            ["PUT", "/boot-source"],
            ["PUT", "/drives/rootfs"],
            ["PUT", "/network-interfaces/eth0"],
            ["PUT", "/vsock"],
            ["PUT", "/machine-config"],
            ["PUT", "/actions"],
        ]);
        expect(JSON.parse(requests[1]!.body!)).toMatchObject({
            path_on_host: "/var/lib/firemig/sandboxes/s1/rootfs.ext4",
            is_read_only: false,
        });
        expect(JSON.parse(requests[4]!.body!)).toEqual({
            vcpu_count: 2,
            mem_size_mib: 1024,
            smt: false,
            huge_pages: "None",
            track_dirty_pages: false,
            cpu_template: "T2S",
        });
    });

    it("constructs snapshot load without re-sending machine configuration", async () => {
        const requests: UnixHttpRequest[] = [];
        const client = new FirecrackerClient("/fc.socket", async (request) => {
            requests.push(request);
            return { statusCode: 204, headers: {}, body: "" };
        });
        await client.loadSnapshot({
            snapshotPath: "/staging/state",
            memoryPath: "/staging/mem",
            clockRealtime: true,
            networkOverride: { ifaceId: "eth0", hostDevName: "fmtap0" },
            vsockOverride: "/canonical/vsock.socket",
        });
        expect(requests).toHaveLength(1);
        expect(JSON.parse(requests[0]!.body!)).toEqual({
            snapshot_path: "/staging/state",
            mem_backend: { backend_path: "/staging/mem", backend_type: "File" },
            resume_vm: false,
            clock_realtime: true,
            network_overrides: [{ iface_id: "eth0", host_dev_name: "fmtap0" }],
            vsock_override: { uds_path: "/canonical/vsock.socket" },
        });
    });
});
