import { createHash } from "node:crypto";

export interface NetworkIdentity {
    netns: string;
    hostVeth: string;
    hostAddress: string;
    namespaceAddress: string;
    subnet: string;
}

export function deriveNetworkIdentity(
    workerId: string,
    sandboxId: string,
    attempt = 0,
): NetworkIdentity {
    if (!Number.isSafeInteger(attempt) || attempt < 0)
        throw new Error("Invalid network allocation attempt");
    const digest = createHash("sha256").update(`${workerId}\0${sandboxId}\0${attempt}`).digest();
    const name = digest.toString("hex").slice(0, 11);
    const second = 64 + (digest[6]! % 64);
    const third = digest[7]!;
    const fourth = (digest[8]! % 64) * 4;
    return {
        netns: `fmn${name}`,
        hostVeth: `fmv${name}`,
        hostAddress: `10.${second}.${third}.${fourth + 1}/30`,
        namespaceAddress: `10.${second}.${third}.${fourth + 2}/30`,
        subnet: `10.${second}.${third}.${fourth}/30`,
    };
}

export function addressWithoutPrefix(address: string): string {
    return address.split("/", 1)[0]!;
}

export function deterministicHostPort(
    portBase: number,
    workerId: string,
    sandboxId: string,
    guestPort: number,
): number {
    if (!Number.isInteger(portBase) || portBase < 1 || portBase > 65_535)
        throw new Error("portBase must be between 1 and 65535");
    if (!Number.isInteger(guestPort) || guestPort < 1 || guestPort > 65_535)
        throw new Error("Invalid guest port");
    const available = 65_536 - portBase;
    const digest = createHash("sha256").update(`${workerId}\0${sandboxId}\0${guestPort}`).digest();
    return portBase + (digest.readUInt32BE(0) % available);
}
