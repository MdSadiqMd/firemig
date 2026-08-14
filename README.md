# Live migration task

Build a small system that demonstrates how a running Firecracker microVM could
move from one region to another.

Run a server inside the VM. While a client is connected to it, move the VM from
worker A to worker B. The VM and server process should continue from the same
state and the client should keep receiving data after a short interruption.

You can run this on two cloud hosts in different regions or locally on one Linux
machine with two isolated workers.

## Use Firecracker directly

You must use [Firecracker](https://github.com/firecracker-microvm/firecracker) and
spin up the microVMs yourself.

Your system should start and manage the Firecracker processes, guest kernel,
root filesystem, machine configuration, API sockets, TAP devices and networking.
It should create the snapshots, move the required state and restore the VM on the
destination worker.

Cloud infrastructure is allowed. Ordinary compute instances or bare-metal Linux
hosts with KVM, networking and storage are fine. Do not use the provider's
snapshot, live-migration or managed sandbox API as the implementation. Do not
replace the Firecracker VM with a container, QEMU VM or restarted process.

Firecracker gives you snapshot and restore primitives. It does not give you the
complete migration system. You need to handle:

- compatible source and destination hosts;
- memory and VM state transfer;
- writable disk state;
- a stable client-facing address;
- traffic while the VM is paused;
- destination readiness and source fencing;
- retries, rollback and cleanup; and
- migration progress and failure reporting.

Only one copy of the VM should be active after cutover. If restore fails, the
source VM should be able to resume.

## The minimum we expect

A good baseline solution can be simple:

1. Run two isolated workers on compatible Linux/KVM hosts or on one Linux/KVM
   machine.
2. Create and boot a Firecracker VM on worker A.
3. Run a small counter server inside the VM.
4. Connect a client through a stable TCP or HTTP streaming proxy.
5. Pause the VM and create a full Firecracker snapshot.
6. Copy the VM state, memory and required disk state to worker B.
7. Restore the snapshot in a new Firecracker process on worker B.
8. Point the proxy at the restored VM and resume the client stream.
9. Stop worker A only after worker B is healthy.

The external client connection to the proxy should remain open. The proxy may
open a new internal connection to the restored VM. You do not need to preserve a
raw TCP connection between the proxy and the guest.

## Control API

Build a small HTTP API and TypeScript SDK for controlling the system. It should
roughly support:

```text
POST /v1/sandboxes                         create a Firecracker VM
POST /v1/sandboxes/:id/commands            run a command
PUT  /v1/sandboxes/:id/files               write a file
POST /v1/sandboxes/:id/ports               expose a guest port
POST /v1/sandboxes/:id/migrations          start a migration
GET  /v1/sandboxes/:id/migrations/:move    read migration progress
GET  /v1/sandboxes/:id                     inspect the VM and current region
```

The SDK should feel approximately like this:

```ts
const sandbox = await client.sandboxes.create({
  region: "worker-a",
  cpu: 2,
  memoryMb: 2048,
});

await sandbox.files.write("/opt/demo/server.py", serverSource);
await sandbox.commands.run({
  command: "python3 /opt/demo/server.py",
  background: true,
});

const port = await sandbox.ports.expose({ guestPort: 8080 });
const migration = await sandbox.migrate({ destination: "worker-b" });

for await (const progress of migration.watch()) {
  console.log(progress.phase, progress.bytesTransferred);
}
```

Choose the missing request, response, idempotency and failure semantics.
The API and SDK only need enough functionality to run the demonstration. They do
not need to be a general-purpose sandbox platform.

## Show that it really migrated

The server inside the VM can emit something like this every second over one
long-lived connection:

```json
{"boot_id":"8b9...","pid":417,"counter":38,"time":"2026-07-25T10:00:00Z"}
```

Provide an automated demo that:

1. creates a Firecracker sandbox on worker A;
2. writes and starts the server inside it;
3. exposes the port and opens one streaming connection;
4. collects events before migration;
5. migrates the running VM to worker B without reopening the client connection;
6. continues collecting events after migration; and
7. reports total migration time, VM pause time, longest event gap, bytes moved
   and whether the boot ID, PID and counter remained continuous.

Booting a new VM and restarting the server does not count. Neither does hiding a
restart behind a reconnecting client.

## Testing locally

Local support is recommended, not required. It is useful for developing and
demonstrating the migration without paying for two KVM-capable cloud hosts.

The local setup should run on a Linux machine with KVM and read/write access to
`/dev/kvm`. It may run the source and destination workers on one Linux machine,
but they should have separate Firecracker processes, working directories, API
sockets and network namespaces or equivalent isolation.

If you support local testing, someone reviewing the project should be able to
run commands equivalent to:

```bash
make setup       # check KVM and fetch pinned Firecracker, kernel and rootfs assets
make local-up    # start the proxy and two isolated workers
make demo        # run the connected-server migration demonstration
make test        # run correctness and failure tests
```

The command names can differ. The experience should not require us to manually
assemble a kernel, rootfs, TAP device or Firecracker API request.

Firecracker requires Linux and KVM. If you develop on macOS or Windows, use a
Linux machine with nested virtualization support or a remote Linux KVM host.

If you choose a cloud deployment instead, provide a reproducible way to create
the two compatible hosts and run the same demo there.

## Reliability first

We will test successful migration, an unavailable destination, an interrupted
state transfer, a repeated migration request and A → B → A migration while the
workload is active.

Use a reliable full snapshot path. Measure the VM pause and network gap instead
of claiming zero downtime.

## Not required

You do not need to build:

- a production multi-tenant sandbox platform;
- a deployment in two paid bare-metal cloud regions;
- zero-downtime or raw guest TCP connection migration;
- differential snapshots, dirty-page pre-copy or demand paging;
- a distributed scheduler; or
- support for large VMs or many concurrent migrations.

These are useful follow-up ideas after the local path is reliable. Briefly
explain how you would take the design from two local workers to two compatible
hosts in different regions.

Aim to complete the core task in roughly 8–12 focused hours. Prefer a smaller
system that works and recovers correctly over an ambitious incomplete one.

## Quality

We care about reliability, code quality, tests, documentation and project
structure. Using coding agents is fine, but you own the complete result.

Share the code, setup instructions for your chosen environment, automated demo,
tests and the important decisions you made. If you deploy it in the cloud, share
an endpoint or a clear way for us to run the demonstration.

Useful Firecracker documentation:

- [Getting started](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)
- [Snapshot support](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/snapshot-support.md)
- [Snapshot compatibility](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/versioning.md)
- [Network setup](https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md)
