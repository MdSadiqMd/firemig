# Firemig

Live-migrate a running Firecracker microVM between regions without losing the workload.

## Problem

Migrating a running VM across regions is usually a provider-managed feature: you click "live migrate" and the cloud does everything. This project does it the hard way — and that's the point.

We build the complete migration system on top of [Firecracker's](https://github.com/firecracker-microvm/firecracker) raw snapshot primitives: source and destination worker agents, a control plane with durable state, a session gateway that keeps the client's connection alive across cutover, a Python guest agent over AF_VSOCK, an SDK, and an automated demo that proves the migration is real.

The core insight: **a migration is not a reboot**. Booting a fresh VM on the destination and reconnecting the client does not count. The same boot ID, the same PID, a monotonic counter and one unbroken client connection — after a pause measured in seconds, not minutes — are the only evidence that the VM actually moved.

This project deliberately uses Firecracker's snapshot/restore primitives and nothing else from the provider's migration stack. No managed sandbox API, no provider snapshots, no QEMU, no containers. Memory, VM state, writable disk and networking are transferred by our own code, and only one copy of the VM is ever active after cutover.

## Table of Contents

- [Architecture Diagram](#architecture-diagram)
- [Component Breakdown](#component-breakdown)
- [How the Migration Works](#how-the-migration-works)
  - [The minimum we expect](#the-minimum-we-expect)
  - [Reliability first](#reliability-first)
- [Control API and SDK](#control-api-and-sdk)
- [Proving It Really Migrated](#proving-it-really-migrated)
- [Measured Numbers(📏)](#measured-numbers)
- [Workflows](#workflows)
  - [Workflow 1: Local (nested-KVM VM or Linux host)](#workflow-1-local-nested-kvm-vm-or-linux-host)
  - [Workflow 2: GCP single-host](#workflow-2-gcp-single-host)
  - [Workflow 3: GCP two-region](#workflow-3-gcp-two-region)
- [Setup](#setup)
- [Testing](#testing)
- [Not Required](#not-required)
- [Quality](#quality)

## Architecture Diagram

```mermaid
sequenceDiagram
    autonumber

    participant Client as SDK / Demo (TS)
    participant Coord as Coordinator (Elixir)<br/>Phoenix + SQLite WAL
    participant Broker as Redpanda<br/>firemig.commands
    participant Gateway as Session Gateway (Elixir)<br/>Thousand Island
    participant WorkerA as Worker A (Node)<br/>Firecracker API + namespaces
    participant FC as Firecracker v1.16.1
    participant Guest as Guest (Python)<br/>AF_VSOCK agent
    participant WorkerB as Worker B (Node)
    participant S3 as Artifact Store<br/>Local / GCS

    rect rgb(40, 50, 70)
        Note over Client,WorkerA: SANDBOX LIFECYCLE
        Client->>+Coord: POST /v1/sandboxes
        Coord->>Coord: durable phase transitions (SQLite WAL)
        Coord-->>-Client: sandbox id
        Client->>Coord: POST /v1/sandboxes/:id/commands
        Coord->>+Broker: publish command (userId key, partition 0)
        Broker-->>Coord: ack
        Coord->>+WorkerA: enqueue command
        WorkerA->>FC: start Firecracker, boot kernel + rootfs
        FC-->>Guest: boot
        Guest->>Guest: connect AF_VSOCK agent
        WorkerA->>+Guest: run command
        Guest-->>-WorkerA: exit status / output
        WorkerA-->>Coord: result
        Coord-->>-Client: broadcast result (WebSocket)
    end

    rect rgb(50, 60, 50)
        Note over Client,WorkerB: MIGRATION (A → B)
        Client->>+Coord: POST /v1/sandboxes/:id/migrations
        Coord->>Coord: gate: destination ready (agent + API socket)
        Coord->>+WorkerA: freeze + snapshot (memory, VM state, disk)
        WorkerA->>WorkerA: write snapshot artifacts
        alt co-located workers
            WorkerA->>WorkerB: atomic hard links
        else separate hosts
            WorkerA->>S3: resumable verified transfer (SHA-256)
            S3-->>WorkerB: artifacts
        end
        WorkerA->>WorkerB: restore + resume
        WorkerB->>+Guest: resume (same state, same PID)
        Gateway->>Gateway: replace internal guest connection only
        Gateway->>Coord: cutover committed (intent)
        Coord->>+WorkerA: fence + kill source
        WorkerA->>WorkerA: quarantine sandbox dir
        Coord-->>-Client: migration done (phases + bytes)
    end

    rect rgb(60, 50, 50)
        Note over Client,Coord: CONTINUITY
        Client->>+Gateway: one long-lived TCP/WS stream (pre-migration)
        Gateway->>Guest: stream through worker relay
        Note over Gateway: external socket is NEVER closed
        Gateway->>Guest: post-cutover: fresh internal connection
        Client-->>Gateway: still receiving events, boot ID/PID unchanged
        Client->>Coord: GET /v1/sandboxes/:id/migrations/:id (progress)
    end
```

| Layer | Language | Role |
|---|---|---|
| **Coordinator** | Elixir/Phoenix | Control API, SQLite WAL durability, idempotency, reconciliation, SSE |
| **Session gateway** | Elixir/OTP | Thousand Island; external sockets survive worker cutover |
| **Worker** | TypeScript/Node | Direct Firecracker API, mount/net namespaces, snapshots, transfers, fencing |
| **SDK + demo** | TypeScript | Typed client for the control API + automated migration demo |
| **Guest agent** | Python | Dependency-free AF_VSOCK control inside the VM |
| **Command broker** | Redpanda `v25.2.7` | Durable, ordered command queue (one partition, loopback-only listeners) |
| **Infrastructure** | Terraform | Bootstrap state, one-host and two-region GCP topologies |

## How the Migration Works

The reliable baseline uses a **full Firecracker snapshot** — no dirty-page tracking, no pre-copy, no demand paging. The proxy owns the external socket and replaces only its internal guest connection. Source rollback is allowed only before the destination resume intent is committed; after that, only the destination copy may run.

The migration runs in these phases:

```
PHASE 1 — Preflight & gate
    Destination agent reports dependencies ready
    Destination Firecracker API process is listening
    → migration cannot pass RESERVING/PRESTAGING until both are true

PHASE 2 — Pause & snapshot (source)
    Source VM is paused
    Full snapshot: memory + VM state + writable disk state
    Fenced: cutover intent committed

PHASE 3 — Transfer
    Co-located workers: atomic hard links for immutable artifacts
    Separate hosts: resumable SHA-256 HTTP transfer
    → 2.222s end-to-end with hard links vs 24.831s over transfer

PHASE 4 — Restore & resume (destination)
    Snapshot restored in a fresh Firecracker process on worker B
    Same boot ID, same PID, same in-memory state
    Worker B health is verified BEFORE worker A is touched

PHASE 5 — Cutover & fencing
    Gateway points at the restored VM; client stream resumes
    Coordinator fences and kills source Firecracker
    Source sandbox moves to quarantine (safe to delete after retention)
    epochs.json persists fencing history → rejects stale requests, supports B → A later
```

### The minimum we expect

A good baseline is simple and reliable:

1. Run two isolated workers on compatible Linux/KVM hosts (or one Linux/KVM machine).
2. Create and boot a Firecracker VM on worker A.
3. Run a small counter server inside the VM.
4. Connect a client through a stable TCP or HTTP streaming proxy.
5. Pause the VM and create a full Firecracker snapshot.
6. Copy VM state, memory and required disk state to worker B.
7. Restore the snapshot in a new Firecracker process on worker B.
8. Point the proxy at the restored VM and resume the client stream.
9. Stop worker A only after worker B is healthy.

The external client connection stays open the whole time. The proxy may open a fresh internal connection to the restored VM — a raw TCP connection between proxy and guest does not need to survive.

### Reliability first

The system is tested against: successful migration, an **unavailable destination**, an **interrupted state transfer**, a **repeated migration request**, and **A → B → A** migration while the workload is active. We measure VM pause and network gap — we never claim zero downtime.

## Control API and SDK

A small HTTP API and TypeScript SDK control the system:

```text
POST /v1/sandboxes                         create a Firecracker VM
POST /v1/sandboxes/:id/commands            run a command
PUT  /v1/sandboxes/:id/files               write a file
POST /v1/sandboxes/:id/ports               expose a guest port
POST /v1/sandboxes/:id/migrations          start a migration
GET  /v1/sandboxes/:id/migrations/:move    read migration progress
GET  /v1/sandboxes/:id                     inspect the VM and current region
```

The SDK feels roughly like this:

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

Missing request/response, idempotency and failure semantics were chosen deliberately; the API is scoped to running the demonstration, not to being a general-purpose sandbox platform. Command continuity runs over one authenticated Phoenix WebSocket per user: commands submitted while a migration is active are published to Redpanda partition 0 keyed by `userId`, projected durably into SQLite, and replayed in offset order after `DONE`.

## Proving It Really Migrated

The server inside the VM emits this every second over one long-lived connection:

```json
{"boot_id":"8b9...","pid":417,"counter":38,"time":"2026-07-25T10:00:00Z"}
```

The automated demo:

1. creates a Firecracker sandbox on worker A;
2. writes and starts the server inside it;
3. exposes the port and opens one streaming connection;
4. collects events before migration;
5. migrates the running VM to worker B without reopening the client connection;
6. continues collecting events after migration; and
7. reports total migration time, VM pause time, longest event gap, bytes moved, and whether boot ID, PID and counter remained continuous.

A live verification run: SDK migration A → B with one unchanged external socket — boot ID/PID continuous, counter monotonic, **zero client reconnects**, `1,610,636,578` bytes transferred. The exactly-once stream check delivered all `1..50` values in exact order with zero missing, duplicate, or out-of-order values, and computation was never replayed.

## Measured Numbers(📏)

Measured on the GCP single-host deployment (`n2-standard-4`, `us-east1-b`) and local nested-KVM runs:

| Metric | Value | Notes |
|---|---|---|
| Migration time (hard-link, co-located) | **2.222s** | 256 MiB demo VM; was 24.831s over transfer path |
| Migration time (live, after optimization) | **2.182–2.571s** | Across repeated prod + local verification runs |
| Bytes moved | 1.61 GB | Full snapshot, not dirty pages |
| Client reconnects | **0** | External socket never closed |
| Counter continuity | exact `1..50` | Zero missing/duplicate/out-of-order events |
| Profile (optimized) | 97.84% idle | Firecracker snapshot creation (1.460s) is the dominant phase |

Where the time goes (from `make infra-profile` → `flamegraphs/firemig-migration.svg`): snapshot creation dominates. The hard-link trick removed nearly all transfer cost; the remaining seconds are Firecracker itself, not our plumbing.

## Workflows

Two topologies, one codebase.

### Workflow 1: Local (nested-KVM VM or Linux host)

On Apple M3+ with Lima installed, `make local-up` creates or starts a nested-virtualization Linux VM, selects its rootful Docker context, starts coordinator, proxy, workers and Redpanda, then follows runtime container logs:

```bash
make local-up
# In another terminal:
make demo
make down
```

The Lima instance is `firemig-kvm`, its Docker context is `lima-firemig-kvm`, and the one-time setup is:

```bash
limactl start --name=firemig-kvm --vm-type=vz --nested-virt \
  --cpus=8 --memory=16 --disk=100 \
  --port-forward=4000:4000,static=true \
  --port-forward=8080:8080,static=true \
  --tty=false template:docker-rootful
docker context create lima-firemig-kvm --docker \
  "host=$(limactl list firemig-kvm --format 'unix://{{.Dir}}/sock/docker.sock')"
docker context use lima-firemig-kvm
```

Docker Desktop does not expose `/dev/kvm` — use the Lima context, `make gcp-up`, or another Linux Docker engine that does. On macOS, `make demo` runs inside the runtime container so the raw TCP continuity check does not include Lima's host port-forwarding layer. Set `FIREMIG_FOLLOW_LOGS=0` for detached automation.

### Workflow 2: GCP single-host

The deployed baseline uses one GCE nested-KVM host with **two isolated logical workers**. Both worker directories live on the persistent disk at `/var/lib/runable`; Firecracker processes, API sockets, mount namespaces, network namespaces and working paths stay separate. Co-located migrations use atomic hard links for snapshot artifacts. Removing worker A's directory after B's health check does not remove B's link — but deleting the GCE host removes both workers.

The public demo is live at `http://35.185.18.216:4000` (auth values land in the ignored `.run/gcp.env` after `make infra-deploy`). It is **not** a cross-region deployment: `worker-a`/`worker-b` are logical workers, not regions, and the hard-link timing only applies to one-host mode.

### Workflow 3: GCP two-region

For the real thing: `infra/gcp/environments/two-region` deploys separate hosts that exchange **independently verified artifacts** over the private network — resumable SHA-256 transfer, no hard links. This is the topology that would take the design to two regions; it exists as a Terraform root but is not deployed.

## Setup

1. Clone and prepare the environment:

```bash
git clone <repo-url>
cd runable
```

2. Install dependencies and assets:

```bash
make setup
```

`make setup` verifies Linux, `/dev/kvm`, supported host kernel and disk space; downloads and verifies Firecracker `v1.16.1`; downloads the pinned guest kernel and rootfs; converts the rootfs to writable ext4; and injects the vsock guest agent. Runtime credentials are generated under the ignored `.run/` directory.

3. Build everything (TypeScript packages, coordinator, proxy):

```bash
make build
```

4. Start the stack:

```bash
make local-up    # macOS: Lima nested-KVM VM + Docker stack
                 # Linux: preflight + build + systemd-style services
```

On Linux, `make local-up` also reconciles Redpanda through Docker before starting application services. Kafka (`9092`), HTTP Proxy (`8082`) and admin (`9644`) bind only to host loopback; broker data persists under the Firemig data root.

5. Run the demo and tests:

```bash
make demo
make test
make down
```

6. GCP (optional):

```bash
# Configure infra/gcp/environments/single-host/terraform.tfvars, then:
make infra-up        # bootstrap state backend → init → apply → deploy
make infra-demo      # run the SDK migration test against the deployed endpoint
make infra-profile   # deploy + strict test + interactive perf flamegraph
```

See [`infra/gcp/README.md`](infra/gcp/README.md) and [`docs/decisions.md`](docs/decisions.md).

## Testing

`make test` runs the full correctness and failure suite:

```bash
# syntax-check all shell scripts, then:
pnpm typecheck && pnpm test              # SDK, demo, worker
mix precommit                             # coordinator
mix format --check-formatted --warnings-as-errors && mix test   # proxy
python3 -m py_compile guest/agent.py      # guest agent
terraform -chdir=infra/gcp/environments/single-host validate
```

Failure coverage includes an unavailable destination, an interrupted state transfer, and repeated/overlapping migration requests. The destination gate cannot be passed until the destination agent and Firecracker API are actually ready — source pause only happens after that.

Operational notes:

- After cutover, the coordinator fences and kills source Firecracker and moves its sandbox under worker A's quarantine. Deleting the quarantined sandbox after the retention window is safe — worker B has its own directory entry for every required inode. Do **not** delete the worker A root while the system runs: it holds `epochs.json`, the fencing history that rejects stale requests and enables a later B → A migration.
- The workflow is tested as a bare VM directly managed by the worker. We start and manage Firecracker processes, guest kernel, rootfs, machine config, API sockets, TAP devices and networking ourselves — the provider's snapshot, live-migration and managed sandbox APIs are not used as the implementation.
- Compatible source/destination hosts, memory and VM state transfer, writable disk state, a stable client-facing address, traffic while paused, destination readiness, source fencing, retries, rollback, cleanup, and progress/failure reporting are all handled in the migration runner.

## Not Required

The following were deliberately out of scope (and are useful follow-ups after the reliable baseline):

- a production multi-tenant sandbox platform;
- a deployment in two paid bare-metal cloud regions;
- zero-downtime or raw guest TCP connection migration;
- differential snapshots, dirty-page pre-copy or demand paging;
- a distributed scheduler; or
- support for large VMs or many concurrent migrations.

The path from two local workers to two compatible hosts in different regions is the `two-region` Terraform root: separate hosts, independently verified artifacts, resumable private-network transfer, and the same gateway cutover — just without hard links. The core task is built to be reliable first: a smaller system that works and recovers correctly beats an ambitious incomplete one.

## Quality

We care about reliability, code quality, tests, documentation and project structure. The repo ships the code, setup instructions for local and GCP, an automated demo, failure tests, and the important decisions recorded in [`docs/decisions.md`](docs/decisions.md) with an architecture overview in [`docs/diagrams.md`](docs/diagrams.md). The deployed endpoint at `http://35.185.18.216:4000` demonstrates the full flow.

Useful Firecracker documentation:

- [Getting started](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)
- [Snapshot support](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/snapshot-support.md)
- [Snapshot compatibility](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/versioning.md)
- [Network setup](https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md)
