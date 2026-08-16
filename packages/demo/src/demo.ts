import { sleep } from "@firemig/common";
import { FiremigClient } from "@firemig/sdk";
import { RawTcpCollector } from "./tcp.js";
import { counterServerSource } from "./server-source.js";
import { validateContinuity, type ValidationReport } from "./validator.js";

export interface DemoOptions {
    client: FiremigClient;
    source?: string;
    destination?: string;
    cpu?: number;
    memoryMb?: number;
    preMigrationEvents?: number;
    totalEvents?: number;
    eventTimeoutMs?: number;
}

export async function runDemo(options: DemoOptions): Promise<ValidationReport> {
    const preCount = options.preMigrationEvents ?? 15;
    const totalEvents = options.totalEvents ?? 50;
    const timeout = options.eventTimeoutMs ?? 120_000;
    const sandbox = await options.client.sandboxes.create({
        region: options.source ?? "worker-a",
        cpu: options.cpu ?? 2,
        memoryMb: options.memoryMb ?? 256,
    });
    await sandbox.files.write("/opt/demo/server.py", counterServerSource, { mode: 0o755 });
    await sandbox.commands.run({ command: "python3 /opt/demo/server.py", background: true });
    const serverDeadline = Date.now() + 30_000;
    while (true) {
        const readiness = await sandbox.commands.run({
            command:
                "python3 -c \"import socket; socket.create_connection(('127.0.0.1', 8080), 1).close()\"",
        });
        if (readiness.exitCode === 0) break;
        if (Date.now() >= serverDeadline)
            throw new Error("Guest counter server did not become ready");
        await sleep(100);
    }
    const port = await sandbox.ports.expose({ guestPort: 8080, sequenceAware: true });
    const collector = new RawTcpCollector(port.proxyHost, port.proxyPort);
    await collector.connect();
    try {
        await collector.waitForCount(preCount, timeout);
        const started = Date.now();
        const migration = await sandbox.migrate({ destination: options.destination ?? "worker-b" });
        const queuedCommandKey = `demo-redpanda-command-${sandbox.info.id}`;
        const queuedCommand = await sandbox.commands.run(
            { command: "printf redpanda-replayed > /tmp/firemig-queued-command" },
            {
                idempotencyKey: queuedCommandKey,
                awaitCompletion: true,
                signal: AbortSignal.timeout(timeout),
            },
        );
        const queuedCommandAccepted = queuedCommand.queued === true;
        const queuedCommandReplayed = queuedCommand.exitCode === 0;
        let bytesTransferred = 0;
        for await (const progress of migration.watch())
            bytesTransferred = Math.max(bytesTransferred, progress.bytesTransferred);
        const totalMigrationMs = Date.now() - started;
        await collector.waitForCount(totalEvents, timeout);
        const status = await migration.get();
        if (collector.parseErrors.length > 0) throw collector.parseErrors[0];
        return validateContinuity({
            observations: collector.observations,
            totalMigrationMs,
            vmPauseMs: status.metrics?.vmPauseMs,
            bytesTransferred: Math.max(bytesTransferred, status.bytesTransferred),
            reconnectCount: collector.reconnectCount,
            expectedStart: 1,
            expectedEnd: totalEvents,
            queuedCommandAccepted,
            queuedCommandReplayed,
        });
    } finally {
        collector.close();
        options.client.close();
    }
}
