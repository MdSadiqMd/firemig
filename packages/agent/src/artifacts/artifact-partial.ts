import type { Hash } from "node:crypto";
import { dirname } from "node:path";
import type { ArtifactDescriptor } from "@firemig/common";
import { ErrorCode, FiremigError } from "@firemig/common";
import type { FileSystemAdapter } from "../platform/adapters.js";

/** Rehashes an existing `.partial` so an interrupted transfer resumes at a verified boundary. */
export async function resumeFromPartial(
    fs: FileSystemAdapter,
    partialPath: string,
    declaredSize: number,
    hash: Hash,
): Promise<number> {
    try {
        const partial = await fs.stat(partialPath);
        if (!partial.isFile() || partial.size > declaredSize) {
            await fs.rm(partialPath, { force: true });
            return 0;
        }
        for await (const chunk of fs.createReadStream(partialPath)) hash.update(chunk as Buffer);
        return partial.size;
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
        return 0;
    }
}

export async function verifyOrDiscard(
    fs: FileSystemAdapter,
    partialPath: string,
    descriptor: ArtifactDescriptor,
    received: number,
    hash: Hash,
): Promise<void> {
    const digest = hash.digest("hex");
    if (received === descriptor.size && digest === descriptor.sha256) return;

    await fs.rm(partialPath, { force: true });
    throw new FiremigError(
        {
            code: ErrorCode.ArtifactHashMismatch,
            message: "Transferred artifact failed size or SHA-256 verification",
            retryable: true,
            details: {
                expectedSize: descriptor.size,
                actualSize: received,
                expectedSha256: descriptor.sha256,
                actualSha256: digest,
            },
        },
        422,
    );
}

/** Renames into place, then fsyncs the directory so the rename itself is durable. */
export async function commitArtifact(
    fs: FileSystemAdapter,
    partialPath: string,
    destinationPath: string,
): Promise<void> {
    await fs.rename(partialPath, destinationPath);
    const directory = await fs.open(dirname(destinationPath), "r");
    try {
        await directory.sync();
    } finally {
        await directory.close();
    }
}
