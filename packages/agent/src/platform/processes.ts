import type { ProcessAdapter, SpawnedProcess } from "./adapters.js";
import type { CommandPlan } from "../planning/planner.js";

interface SandboxProcesses {
    mountNamespace: SpawnedProcess;
    firecracker: SpawnedProcess;
}

export class ProcessLifecycle {
    private readonly processes = new Map<string, SandboxProcesses>();

    constructor(private readonly adapter: ProcessAdapter) {}

    startMountNamespace(): SpawnedProcess {
        return this.adapter.spawn("unshare", [
            "--mount",
            "--propagation",
            "private",
            "--",
            "sleep",
            "infinity",
        ]);
    }

    async runPlans(plans: readonly CommandPlan[]): Promise<void> {
        for (const plan of plans) await this.adapter.run(plan.file, plan.args);
    }

    async copySparse(source: string, destination: string): Promise<void> {
        await this.adapter.run("cp", [
            "--sparse=always",
            "--reflink=auto",
            "--",
            source,
            destination,
        ]);
    }

    launch(sandboxId: string, mountNamespace: SpawnedProcess, plan: CommandPlan): SpawnedProcess {
        if (this.processes.has(sandboxId))
            throw new Error(`Sandbox ${sandboxId} already has a process`);
        const firecracker = this.adapter.spawn(plan.file, plan.args);
        this.processes.set(sandboxId, { mountNamespace, firecracker });
        return firecracker;
    }

    async stop(sandboxId: string): Promise<void> {
        const processes = this.processes.get(sandboxId);
        if (processes === undefined) return;
        processes.firecracker.kill("SIGKILL");
        processes.mountNamespace.kill("SIGKILL");
        await Promise.allSettled([processes.firecracker.exited, processes.mountNamespace.exited]);
        this.processes.delete(sandboxId);
    }

    running(sandboxId: string): boolean {
        return this.processes.has(sandboxId);
    }
}
