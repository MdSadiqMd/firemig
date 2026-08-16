#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "remote-start must run as root" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
run_dir="$root/.run"
assets="$root/assets"
data_root="/var/lib/runable/firemig"
public_host="${FIREMIG_PUBLIC_HOST:?FIREMIG_PUBLIC_HOST is required}"
coordinator="$root/services/coordinator/_build/prod/rel/firemig_coordinator/bin/firemig_coordinator"
proxy="$root/services/proxy/_build/prod/rel/firemig_proxy/bin/firemig_proxy"

source "$root/scripts/runtime/redpanda-runtime.sh"

mkdir -p "$run_dir/logs" "$data_root/workers/worker-a" "$data_root/workers/worker-b" "$data_root/coordinator"
chmod 0700 "$run_dir"

if [[ ! -f "$run_dir/runtime.env" ]]; then
  cat >"$run_dir/runtime.env" <<EOF
FIREMIG_API_URL=http://${public_host}:4000
FIREMIG_API_TOKEN=$(openssl rand -hex 32)
FIREMIG_AGENT_TOKEN=$(openssl rand -hex 32)
PROXY_TOKEN=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
REDPANDA_HTTP_URL=http://127.0.0.1:8082
EOF
  chmod 0600 "$run_dir/runtime.env"
fi

ensure_redpanda_runtime_env "$run_dir/runtime.env"

set -a
source "$run_dir/runtime.env"
set +a

firecracker_sha="$(sha256sum "$assets/firecracker" | cut -d ' ' -f 1)"
kernel_sha="$(sha256sum "$assets/vmlinux-6.1.155" | cut -d ' ' -f 1)"
cpu_vendor="$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_model="$(lscpu | awk -F: '/Model name/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_family="$(lscpu | awk -F: '/CPU family/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_stepping="$(lscpu | awk -F: '/Stepping/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"

start_redpanda "$data_root/redpanda"

pkill -TERM -f "$root/packages/agent/dist/cli.js" 2>/dev/null || true
for _attempt in $(seq 1 40); do
  pgrep -f "$root/packages/agent/dist/cli.js" >/dev/null || break
  sleep 0.25
done
pkill -KILL -f "$root/packages/agent/dist/cli.js" 2>/dev/null || true
rm -f "$run_dir/worker-a.pid" "$run_dir/worker-b.pid"

start_agent() {
  local worker_id="$1"
  local agent_port="$2"
  local port_base="$3"
  local pid_file="$run_dir/$worker_id.pid"
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    return
  fi
  nohup env \
    FIREMIG_WORKER_ID="$worker_id" FIREMIG_REGION="$worker_id" \
    FIREMIG_WORKDIR="$data_root/workers/$worker_id" \
    FIREMIG_AGENT_PORT="$agent_port" FIREMIG_PORT_BASE="$port_base" \
    FIREMIG_AGENT_TOKEN="$FIREMIG_AGENT_TOKEN" \
    FIREMIG_PEER_URLS="worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102" \
    FIREMIG_SHARED_WORKER_ROOT="$data_root/workers" \
    FIREMIG_PROXY_HOST=127.0.0.1 \
    FIRECRACKER_BINARY="$assets/firecracker" FIRECRACKER_VERSION=v1.16.1 \
    FIRECRACKER_SHA256="$firecracker_sha" FIRECRACKER_SNAPSHOT_FORMAT=3.0.0 \
    FIREMIG_KERNEL="$assets/vmlinux-6.1.155" FIREMIG_KERNEL_SHA256="$kernel_sha" \
    FIREMIG_ROOTFS="$assets/rootfs.ext4" FIREMIG_CPU_TEMPLATE=T2S \
    FIREMIG_CPU_VENDOR="$cpu_vendor" FIREMIG_CPU_MODEL="$cpu_model" \
    FIREMIG_CPU_FAMILY="$cpu_family" FIREMIG_CPU_STEPPING="$cpu_stepping" \
    node "$root/packages/agent/dist/cli.js" >"$run_dir/logs/$worker_id.log" 2>&1 &
  echo "$!" >"$pid_file"
}

start_agent worker-a 4101 10000
start_agent worker-b 4102 20000

pkill -TERM -f "$root/services/proxy/_build/prod/rel/firemig_proxy/erts-.*/bin/beam.smp" 2>/dev/null || true
for _attempt in $(seq 1 40); do
  pgrep -f "$root/services/proxy/_build/prod/rel/firemig_proxy/erts-.*/bin/beam.smp" >/dev/null || break
  sleep 0.25
done
pkill -KILL -f "$root/services/proxy/_build/prod/rel/firemig_proxy/erts-.*/bin/beam.smp" 2>/dev/null || true
PROXY_TOKEN="$PROXY_TOKEN" ADMIN_PORT=4200 "$proxy" daemon

database_path="$data_root/coordinator/control.db"
DATABASE_PATH="$database_path" SECRET_KEY_BASE="$SECRET_KEY_BASE" "$coordinator" eval "FiremigCoordinator.Release.migrate()"
pkill -TERM -f "$root/services/coordinator/_build/prod/rel/firemig_coordinator/erts-.*/bin/beam.smp" 2>/dev/null || true
for _attempt in $(seq 1 40); do
  pgrep -f "$root/services/coordinator/_build/prod/rel/firemig_coordinator/erts-.*/bin/beam.smp" >/dev/null || break
  sleep 0.25
done
pkill -KILL -f "$root/services/coordinator/_build/prod/rel/firemig_coordinator/erts-.*/bin/beam.smp" 2>/dev/null || true
PHX_SERVER=true PORT=4000 PHX_HOST="$public_host" DATABASE_PATH="$database_path" \
  SECRET_KEY_BASE="$SECRET_KEY_BASE" API_TOKEN="$FIREMIG_API_TOKEN" \
  WORKER_TOKEN="$FIREMIG_AGENT_TOKEN" PROXY_TOKEN="$PROXY_TOKEN" \
  REDPANDA_HTTP_URL="$REDPANDA_HTTP_URL" \
  PROXY_URL=http://127.0.0.1:4200 PROXY_PUBLIC_HOST="$public_host" DEFAULT_PROXY_PORT=8080 \
  WORKER_URLS=worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102 \
  "$coordinator" daemon

for url in http://127.0.0.1:4101/healthz http://127.0.0.1:4102/healthz http://127.0.0.1:4200/health http://127.0.0.1:4000/healthz; do
  for _attempt in $(seq 1 120); do
    curl -fsS --connect-timeout 1 --max-time 2 "$url" >/dev/null && break
    sleep 0.25
  done
  curl -fsS --connect-timeout 1 --max-time 2 "$url" >/dev/null
done

echo "FIREMIG_API_URL=http://${public_host}:4000"
echo "FIREMIG_API_TOKEN=${FIREMIG_API_TOKEN}"
