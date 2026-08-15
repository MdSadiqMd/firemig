import type { ArtifactDescriptor } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";
import type { FileSystemAdapter } from "../platform/adapters.js";

export interface ArtifactRange {
    start: number;
    end: number;
}

export interface ArtifactServeResult {
    status: 200 | 206;
    headers: Record<string, string>;
    stream: NodeJS.ReadableStream;
}

export function parseRangeHeader(
    header: string | undefined,
    size: number,
): ArtifactRange | undefined {
    if (header === undefined) return undefined;
    const match = /^bytes=(\d+)-(\d*)$/.exec(header);
    if (match === null) throw rangeError("Invalid Range header");
    const start = Number(match[1]);
    const requestedEnd = match[2] === "" ? size - 1 : Number(match[2]);
    if (
        !Number.isSafeInteger(start) ||
        !Number.isSafeInteger(requestedEnd) ||
        start < 0 ||
        start >= size ||
        requestedEnd < start
    ) {
        throw rangeError("Range is outside the artifact");
    }
    return { start, end: Math.min(requestedEnd, size - 1) };
}

export async function openArtifactRange(
    fs: FileSystemAdapter,
    path: string,
    descriptor: ArtifactDescriptor,
    rangeHeader?: string,
): Promise<ArtifactServeResult> {
    const stat = await fs.stat(path);
    if (!stat.isFile() || stat.size !== descriptor.size)
        throw new Error("Artifact changed after manifest creation");
    const range = parseRangeHeader(rangeHeader, stat.size);
    const start = range?.start ?? 0;
    const end = range?.end ?? stat.size - 1;
    return {
        status: range === undefined ? 200 : 206,
        headers: {
            "accept-ranges": "bytes",
            "content-type": "application/octet-stream",
            "content-length": String(end - start + 1),
            "x-artifact-sha256": descriptor.sha256,
            ...(range === undefined
                ? {}
                : { "content-range": `bytes ${start}-${end}/${stat.size}` }),
        },
        stream: fs.createReadStream(path, { start, end }),
    };
}

function rangeError(message: string): FiremigError {
    return new FiremigError(
        { code: ErrorCode.ArtifactRangeInvalid, message, retryable: false },
        416,
    );
}
