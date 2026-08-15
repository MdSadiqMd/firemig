import { dirname, join } from "node:path";
import { ErrorCode, FiremigError } from "@firemig/common";
import type { FileSystemAdapter } from "./adapters.js";

interface EpochDocument {
    version: 1;
    epochs: Record<string, number>;
}

export class EpochStore {
    private readonly epochs = new Map<string, number>();
    private mutation = Promise.resolve();

    constructor(
        private readonly path: string,
        private readonly fs: FileSystemAdapter,
    ) {}

    async load(): Promise<void> {
        try {
            const parsed = JSON.parse(
                await this.fs.readFile(this.path, "utf8"),
            ) as Partial<EpochDocument>;
            if (parsed.version !== 1 || typeof parsed.epochs !== "object" || parsed.epochs === null)
                throw new Error("Invalid epoch document");
            this.epochs.clear();
            for (const [id, epoch] of Object.entries(parsed.epochs)) {
                if (!Number.isSafeInteger(epoch) || epoch < 0)
                    throw new Error(`Invalid epoch for ${id}`);
                this.epochs.set(id, epoch);
            }
        } catch (error) {
            if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
        }
    }

    get(sandboxId: string): number {
        return this.epochs.get(sandboxId) ?? 0;
    }

    accept(
        sandboxId: string,
        requestedEpoch: number,
    ): Promise<{ previous: number; advanced: boolean }> {
        if (!Number.isSafeInteger(requestedEpoch) || requestedEpoch < 0)
            return Promise.reject(new Error("Invalid epoch"));
        const operation = this.mutation.then(async () => {
            const previous = this.get(sandboxId);
            if (requestedEpoch < previous) {
                throw new FiremigError(
                    {
                        code: ErrorCode.Fenced,
                        message: `Epoch ${requestedEpoch} is stale; worker has accepted ${previous}`,
                        retryable: false,
                        details: { sandboxId, requestedEpoch, acceptedEpoch: previous },
                    },
                    409,
                );
            }
            if (requestedEpoch > previous) {
                this.epochs.set(sandboxId, requestedEpoch);
                try {
                    await this.persist();
                } catch (error) {
                    if (previous === 0) this.epochs.delete(sandboxId);
                    else this.epochs.set(sandboxId, previous);
                    throw error;
                }
            }
            return { previous, advanced: requestedEpoch > previous };
        });
        this.mutation = operation.then(
            () => undefined,
            () => undefined,
        );
        return operation;
    }

    private async persist(): Promise<void> {
        const directory = dirname(this.path);
        await this.fs.mkdir(directory, { recursive: true });
        const temporary = join(directory, `.${process.pid}.${Date.now()}.epochs.tmp`);
        const file = await this.fs.open(temporary, "wx", 0o600);
        try {
            const document: EpochDocument = { version: 1, epochs: Object.fromEntries(this.epochs) };
            await file.writeFile(`${JSON.stringify(document)}\n`);
            await file.sync();
        } finally {
            await file.close();
        }
        await this.fs.rename(temporary, this.path);
        const directoryHandle = await this.fs.open(directory, "r");
        try {
            await directoryHandle.sync();
        } finally {
            await directoryHandle.close();
        }
    }
}
