export interface CommandPlan {
    file: string;
    args: readonly string[];
}

/** `ip netns exec <netns> …` — the wrapper every in-namespace command shares. */
export function nsExec(netns: string, ...args: readonly string[]): CommandPlan {
    return { file: "ip", args: ["netns", "exec", netns, ...args] };
}
