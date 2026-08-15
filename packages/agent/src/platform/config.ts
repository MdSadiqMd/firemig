export function parsePeerUrls(input: string | undefined): Readonly<Record<string, string>> {
    if (input === undefined || input.trim() === "") return {};
    const peers: Record<string, string> = {};
    for (const entry of input.split(",")) {
        const separator = entry.indexOf("=");
        if (separator <= 0) throw new Error(`Invalid FIREMIG_PEER_URLS entry: ${entry}`);
        const worker = entry.slice(0, separator).trim();
        const value = entry
            .slice(separator + 1)
            .trim()
            .replace(/\/$/, "");
        if (worker === "" || value === "" || peers[worker] !== undefined)
            throw new Error(`Invalid FIREMIG_PEER_URLS entry: ${entry}`);
        const url = new URL(value);
        if (url.protocol !== "http:" && url.protocol !== "https:")
            throw new Error(`Peer URL must use HTTP or HTTPS: ${value}`);
        peers[worker] = url.toString().replace(/\/$/, "");
    }
    return peers;
}

export function parsePortBase(input: string | undefined, fallback = 20_000): number {
    const value = input === undefined ? fallback : Number(input);
    if (!Number.isInteger(value) || value < 1 || value > 65_535)
        throw new Error("FIREMIG_PORT_BASE must be an integer from 1 to 65535");
    return value;
}
