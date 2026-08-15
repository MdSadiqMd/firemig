import { join, posix, resolve, sep } from "node:path";

const safeIdentifier = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/;

export function assertIdentifier(value: string, field = "identifier"): void {
    if (!safeIdentifier.test(value)) throw new Error(`Invalid ${field}`);
}

export interface SandboxPaths {
    physicalDirectory: string;
    canonicalDirectory: string;
    apiSocket: string;
    physicalRootfs: string;
    canonicalRootfs: string;
    physicalVsock: string;
    canonicalVsock: string;
    state: string;
    memory: string;
    quarantine: (migrationId: string) => string;
}

export class PathModel {
    readonly workerRoot: string;
    readonly canonicalRoot: string;

    constructor(workerRoot: string, canonicalRoot = "/var/lib/firemig/sandboxes") {
        this.workerRoot = resolve(workerRoot);
        this.canonicalRoot = posix.resolve(canonicalRoot);
    }

    sandbox(id: string, generation = 0): SandboxPaths {
        assertIdentifier(id, "sandbox id");
        if (!Number.isSafeInteger(generation) || generation < 0)
            throw new Error("Invalid generation");
        const physicalDirectory = this.insideWorker("sandboxes", id);
        const canonicalDirectory = posix.join(this.canonicalRoot, id);
        return {
            physicalDirectory,
            canonicalDirectory,
            apiSocket: this.insideWorker("sockets", `${id}.socket`),
            physicalRootfs: join(physicalDirectory, "rootfs.ext4"),
            canonicalRootfs: posix.join(canonicalDirectory, "rootfs.ext4"),
            physicalVsock: join(physicalDirectory, "vsock.socket"),
            canonicalVsock: posix.join(canonicalDirectory, "vsock.socket"),
            state: join(physicalDirectory, `snapshot-${generation}.state`),
            memory: join(physicalDirectory, `memory-${generation}.mem`),
            quarantine: (migrationId) => {
                assertIdentifier(migrationId, "migration id");
                return this.insideWorker("quarantine", migrationId, id);
            },
        };
    }

    private insideWorker(...parts: string[]): string {
        const path = resolve(this.workerRoot, ...parts);
        if (path !== this.workerRoot && !path.startsWith(`${this.workerRoot}${sep}`))
            throw new Error("Path escaped worker root");
        return path;
    }
}
