export interface BootConfiguration {
    kernelPath: string;
    rootfsPath: string;
    vsockPath: string;
    vcpuCount: number;
    memSizeMib: number;
    bootArgs?: string;
    cpuTemplate?: string;
    guestMac?: string;
    tapName?: string;
    mtu?: number;
}

export interface LoadSnapshotRequest {
    snapshotPath: string;
    memoryPath: string;
    resume?: boolean;
    clockRealtime?: boolean;
    networkOverride?: { ifaceId: string; hostDevName: string };
    vsockOverride?: string;
}

const DEFAULT_BOOT_ARGS =
    "console=ttyS0 reboot=k panic=1 pci=off ip=172.16.0.2::172.16.0.1:255.255.255.252::eth0:off";

export function bootSourcePayload(config: BootConfiguration): unknown {
    return {
        kernel_image_path: config.kernelPath,
        boot_args: config.bootArgs ?? DEFAULT_BOOT_ARGS,
    };
}

export function rootfsDrivePayload(config: BootConfiguration): unknown {
    return {
        drive_id: "rootfs",
        path_on_host: config.rootfsPath,
        is_root_device: true,
        is_read_only: false,
        cache_type: "Writeback",
    };
}

export function networkInterfacePayload(config: BootConfiguration): unknown {
    return {
        iface_id: "eth0",
        host_dev_name: config.tapName ?? "fmtap0",
        guest_mac: config.guestMac ?? "06:00:ac:10:00:02",
        rx_rate_limiter: null,
        tx_rate_limiter: null,
        ...(config.mtu === undefined ? {} : { mtu: config.mtu }),
    };
}

export function machineConfigPayload(config: BootConfiguration): unknown {
    return {
        vcpu_count: config.vcpuCount,
        mem_size_mib: config.memSizeMib,
        smt: false,
        huge_pages: "None",
        track_dirty_pages: false,
        ...(config.cpuTemplate === undefined ? {} : { cpu_template: config.cpuTemplate }),
    };
}

export function loadSnapshotPayload(request: LoadSnapshotRequest): unknown {
    return {
        snapshot_path: request.snapshotPath,
        mem_backend: { backend_path: request.memoryPath, backend_type: "File" },
        resume_vm: request.resume ?? false,
        ...(request.clockRealtime === undefined ? {} : { clock_realtime: request.clockRealtime }),
        ...(request.networkOverride === undefined
            ? {}
            : {
                  network_overrides: [
                      {
                          iface_id: request.networkOverride.ifaceId,
                          host_dev_name: request.networkOverride.hostDevName,
                      },
                  ],
              }),
        ...(request.vsockOverride === undefined
            ? {}
            : { vsock_override: { uds_path: request.vsockOverride } }),
    };
}
