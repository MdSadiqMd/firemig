import { createHash } from "node:crypto";
import { basename, dirname } from "node:path";
import type { ArtifactDescriptor, ArtifactKind } from "@firemig/common";
import { ErrorCode, FiremigError, sleep } from "@firemig/common";
import type { FileSystemAdapter, SpawnedProcess } from "../../platform/adapters.js";
import type { VsockGuestClient } from "../../runtime/vsock.js";

export async function describeArtifact(
    fs: FileSystemAdapter,
    kind: ArtifactKind,
    path: string,
): Promise<ArtifactDescriptor> {
    const stat = await fs.stat(path);
    const hash = createHash("sha256");
    for await (const chunk of fs.createReadStream(path)) hash.update(chunk as Buffer);
    return { kind, name: basename(path), size: stat.size, sha256: hash.digest("hex") };
}

/**
 * Shared-root deployments hard-link artifacts instead of copying them, so there is no
 * point hashing the contents — size plus a synthetic marker identifies the generation.
 */
export async function describeSharedArtifact(
    fs: FileSystemAdapter,
    kind: ArtifactKind,
    path: string,
): Promise<ArtifactDescriptor> {
    const stat = await fs.stat(path);
    return {
        kind,
        name: basename(path),
        size: stat.size,
        sha256: `shared-link:${kind}:${stat.size}`,
    };
}

export async function syncSnapshotFiles(
    fs: FileSystemAdapter,
    paths: readonly string[],
): Promise<void> {
    for (const path of paths) {
        const file = await fs.open(path, "r");
        try {
            await file.sync();
        } finally {
            await file.close();
        }
    }
    for (const directoryPath of new Set(paths.map(dirname))) {
        const directory = await fs.open(directoryPath, "r");
        try {
            await directory.sync();
        } finally {
            await directory.close();
        }
    }
}

export async function waitForFile(
    fs: FileSystemAdapter,
    path: string,
    timeoutMs: number,
    process?: SpawnedProcess,
): Promise<void> {
    const controller = new AbortController();
    const timeout = AbortSignal.timeout(timeoutMs);
    const signal = AbortSignal.any([controller.signal, timeout]);
    try {
        const readiness = observeFile(fs, path, signal);
        if (process === undefined) return await readiness;
        await Promise.race([
            readiness,
            process.exited.then(({ code, signal: exitSignal }) => {
                throw new Error(
                    `Process exited before creating ${path}: ${code ?? exitSignal ?? "unknown"}`,
                );
            }),
        ]);
    } catch (error) {
        if (timeout.aborted) throw new Error(`Timed out waiting for ${path}`, { cause: error });
        throw error;
    } finally {
        controller.abort();
    }
}

export async function waitForGuest(
    guest: VsockGuestClient,
    timeoutMs: number,
): Promise<{ bootId: string }> {
    const deadline = Date.now() + timeoutMs;
    let lastError: unknown;
    while (true) {
        const remainingMs = deadline - Date.now();
        if (remainingMs <= 0) break;
        try {
            return await guest.ready(remainingMs);
        } catch (error) {
            lastError = error;
        }
        const backoffMs = Math.min(100, deadline - Date.now());
        if (backoffMs > 0) await sleep(backoffMs);
    }
    throw new FiremigError(
        {
            code: ErrorCode.GuestAgent,
            message: "Guest agent did not become ready",
            retryable: true,
            details: { cause: String(lastError) },
        },
        503,
    );
}

async function observeFile(
    fs: FileSystemAdapter,
    path: string,
    signal: AbortSignal,
): Promise<void> {
    if (await fileExists(fs, path)) return;
    const watcher = fs.watch(dirname(path), { signal });
    if (await fileExists(fs, path)) return;

    for await (const event of watcher) {
        if (event.filename !== null && event.filename !== basename(path)) continue;
        if (await fileExists(fs, path)) return;
    }
}

async function fileExists(fs: FileSystemAdapter, path: string): Promise<boolean> {
    try {
        await fs.stat(path);
        return true;
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
        throw error;
    }
}
