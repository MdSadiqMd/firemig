import { type CommandPlan, nsExec } from "./command-plan.js";
import { assertIdentifier } from "../platform/paths.js";

const GUEST_ADDRESS = "172.16.0.2";
const CLAMPED_MSS = "1360";

export function exposePortPlan(
    netns: string,
    namespaceAddress: string,
    guestPort: number,
    tapName = "fmtap0",
): CommandPlan[] {
    assertIdentifier(netns, "network namespace");
    if (!Number.isInteger(guestPort) || guestPort < 1 || guestPort > 65535)
        throw new Error("Invalid guest port");
    return [
        nsExec(
            netns,
            ...["nft", "add", "rule", "ip", "nat", "prerouting"],
            ...["iifname", "fmv0", "tcp", "dport", String(guestPort)],
            ...["dnat", "to", `${GUEST_ADDRESS}:${guestPort}`],
        ),
        nsExec(
            netns,
            ...["nft", "add", "rule", "ip", "nat", "postrouting"],
            ...["oifname", tapName, "ip", "daddr", GUEST_ADDRESS, "masquerade"],
        ),
        nsExec(
            netns,
            ...["nft", "add", "rule", "inet", "filter", "forward"],
            ...["tcp", "flags", "syn", "tcp", "option", "maxseg", "size", "set", CLAMPED_MSS],
        ),
    ];
}
