import { createHash, type Hash } from "node:crypto";
import { dirname } from "node:path";
import type { ArtifactDescriptor } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";
import type { FileSystemAdapter } from "../platform/adapters.js";
import { type ArtifactHttpClient, fetchArtifact } from "./artifact-http.js";
import { commitArtifact, resumeFromPartial, verifyOrDiscard } from "./artifact-partial.js";

export * from "./artifact-http.js";
export * from "./artifact-range.js";

export interface PullArtifactOptions {
    url: string;
    destinationPath: string;
    descriptor: ArtifactDescriptor;
    fs: FileSystemAdapter;
    http?: ArtifactHttpClient;
    signal?: AbortSignal;
    headers?: Record<string, string>;
    onProgress?: (received: number, total: number) => void;
}

export async function pullArtifact(
    options: PullArtifactOptions,
): Promise<{ resumedAt: number; bytesWritten: number }> {
    const { fs, descriptor, destinationPath } = options;
    const partialPath = `${destinationPath}.partial`;
    await fs.mkdir(dirname(destinationPath), { recursive: true });

    const hash = createHash("sha256");
    const resumedAt = await resumeFromPartial(fs, partialPath, descriptor.size, hash);
    const received =
        resumedAt < descriptor.size
            ? await downloadRemainder(options, partialPath, hash, resumedAt)
            : resumedAt;

    await verifyOrDiscard(fs, partialPath, descriptor, received, hash);
    await commitArtifact(fs, partialPath, destinationPath);
    return { resumedAt, bytesWritten: received - resumedAt };
}

export async function runAbortableOperations<T>(
    operations: ReadonlyArray<(signal: AbortSignal) => Promise<T>>,
): Promise<T[]> {
    const controller = new AbortController();
    const tasks = operations.map(async (operation) => {
        try {
            return await operation(controller.signal);
        } catch (error) {
            controller.abort(error);
            throw error;
        }
    });
    const outcomes = await Promise.allSettled(tasks);
    const failure = outcomes.find(
        (outcome): outcome is PromiseRejectedResult => outcome.status === "rejected",
    );
    if (failure !== undefined) throw failure.reason;
    return outcomes.map((outcome) => (outcome as PromiseFulfilledResult<T>).value);
}

async function downloadRemainder(
    options: PullArtifactOptions,
    partialPath: string,
    hash: Hash,
    resumedAt: number,
): Promise<number> {
    const response = await (options.http ?? fetchArtifact)(options.url, {
        method: "GET",
        headers: {
            ...(options.headers ?? {}),
            ...(resumedAt === 0 ? {} : { range: `bytes=${resumedAt}-` }),
        },
        ...(options.signal === undefined ? {} : { signal: options.signal }),
    });

    const requiredStatus = resumedAt === 0 ? 200 : 206;
    if (response.status !== requiredStatus || response.body === null) {
        throw new FiremigError({
            code: ErrorCode.TransferInterrupted,
            message: `Artifact source returned ${response.status}; expected ${requiredStatus}`,
            retryable: true,
        });
    }

    const remoteHash = response.headers.get("x-artifact-sha256");
    if (remoteHash !== null && remoteHash !== options.descriptor.sha256) {
        throw new FiremigError(
            {
                code: ErrorCode.ArtifactHashMismatch,
                message: "Source manifest hash changed",
                retryable: false,
            },
            409,
        );
    }

    return await writeBody(options, partialPath, hash, resumedAt, response.body);
}

async function writeBody(
    options: PullArtifactOptions,
    partialPath: string,
    hash: Hash,
    resumedAt: number,
    body: AsyncIterable<Uint8Array>,
): Promise<number> {
    let offset = resumedAt;
    const file = await options.fs.open(partialPath, resumedAt === 0 ? "w" : "a", 0o600);
    try {
        for await (const chunk of body) {
            hash.update(chunk);
            await file.writeFile(chunk);
            offset += chunk.byteLength;
            if (offset > options.descriptor.size)
                throw new Error("Artifact source sent more bytes than declared");
            options.onProgress?.(offset, options.descriptor.size);
        }
        await file.sync();
    } finally {
        await file.close();
    }
    return offset;
}
