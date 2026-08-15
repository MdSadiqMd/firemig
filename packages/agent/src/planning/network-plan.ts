import { type CommandPlan, nsExec } from "./command-plan.js";
import { assertIdentifier } from "../platform/paths.js";

export interface NetworkPlanOptions {
    sandboxId: string;
    netns: string;
    hostVeth: string;
    hostAddress: string;
    namespaceAddress: string;
    guestAddress?: string;
    tapName?: string;
    mtu?: number;
}

export function networkCreatePlan(options: NetworkPlanOptions): CommandPlan[] {
    assertIdentifier(options.sandboxId, "sandbox id");
    assertIdentifier(options.netns, "network namespace");
    assertIdentifier(options.hostVeth, "host veth");
    const { netns, hostVeth } = options;
    const tap = options.tapName ?? "fmtap0";
    const mtu = String(options.mtu ?? 1500);
    const peerVeth = `p${hostVeth.slice(1)}`;
    return [
        { file: "ip", args: ["netns", "add", netns] },
        {
            file: "ip",
            args: ["link", "add", hostVeth, "type", "veth", "peer", "name", peerVeth],
        },
        { file: "ip", args: ["link", "set", peerVeth, "netns", netns] },
        nsExec(netns, "ip", "link", "set", peerVeth, "name", "fmv0"),
        { file: "ip", args: ["addr", "add", options.hostAddress, "dev", hostVeth] },
        { file: "ip", args: ["link", "set", hostVeth, "mtu", mtu, "up"] },
        nsExec(netns, "ip", "addr", "add", options.namespaceAddress, "dev", "fmv0"),
        nsExec(netns, "ip", "link", "set", "fmv0", "mtu", mtu, "up"),
        nsExec(netns, "ip", "tuntap", "add", "dev", tap, "mode", "tap"),
        nsExec(netns, "ip", "addr", "add", "172.16.0.1/30", "dev", tap),
        nsExec(netns, "ip", "link", "set", tap, "mtu", mtu, "up"),
        nsExec(netns, "sysctl", "-w", "net.ipv4.ip_forward=1"),
        nsExec(netns, "nft", "add", "table", "ip", "nat"),
        nsExec(netns, ...chain("ip", "nat", "prerouting", "nat", "dstnat")),
        nsExec(netns, ...chain("ip", "nat", "postrouting", "nat", "srcnat")),
        nsExec(netns, "nft", "add", "table", "inet", "filter"),
        nsExec(netns, ...chain("inet", "filter", "forward", "filter", "filter")),
    ];
}

export function networkDeletePlan(netns: string, hostVeth: string): CommandPlan[] {
    assertIdentifier(netns, "network namespace");
    assertIdentifier(hostVeth, "host veth");
    return [
        { file: "ip", args: ["netns", "delete", netns] },
        { file: "ip", args: ["link", "delete", hostVeth] },
    ];
}

/** `nft add chain <family> <table> <name> { type <type> hook <name> priority <priority>; policy accept; }` */
function chain(
    family: string,
    table: string,
    name: string,
    type: string,
    priority: string,
): readonly string[] {
    return [
        "nft",
        "add",
        "chain",
        family,
        table,
        name,
        "{",
        "type",
        type,
        "hook",
        name,
        "priority",
        priority,
        ";",
        "policy",
        "accept",
        ";",
        "}",
    ];
}
