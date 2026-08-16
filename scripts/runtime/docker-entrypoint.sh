#!/usr/bin/env bash
set -euo pipefail

assets="/opt/firemig/assets"
data_root="${FIREMIG_DATA_ROOT:-/var/lib/firemig}"
coordinator="/opt/firemig/coordinator/bin/firemig_coordinator"
proxy="/opt/firemig/proxy/bin/firemig_proxy"
pids=()
API_TOKEN="${API_TOKEN:-$FIREMIG_API_TOKEN}"
WORKER_TOKEN="${WORKER_TOKEN:-$FIREMIG_AGENT_TOKEN}"

cleanup() {
  trap - EXIT INT TERM
  if (( ${#pids[@]} > 0 )); then
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
  while read -r namespace _; do
    [[ "$namespace" == fm* ]] && ip netns delete "$namespace" 2>/dev/null || true
  done < <(ip netns list 2>/dev/null || true)
}
trap cleanup EXIT INT TERM

mkdir -p \
  "$data_root/workers/worker-a" \
  "$data_root/workers/worker-b" \
  "$data_root/coordinator" \
  /run/netns

if [[ ! -c /dev/kvm ]]; then
  echo "warning: /dev/kvm is unavailable; control services will run but Firecracker VM creation will fail" >&2
fi

firecracker_sha="$(sha256sum "$assets/firecracker" | cut -d ' ' -f 1)"
kernel_sha="$(sha256sum "$assets/vmlinux-6.1.155" | cut -d ' ' -f 1)"
architecture="$(uname -m)"
cpu_vendor="$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_model="$(lscpu | awk -F: '/Model name/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_family="$(lscpu | awk -F: '/CPU family/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_stepping="$(lscpu | awk -F: '/Stepping/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_vendor="${cpu_vendor:-$architecture}"
cpu_model="${cpu_model:-$architecture}"
cpu_family="${cpu_family:-$architecture}"
cpu_stepping="${cpu_stepping:-0}"

if [[ "$architecture" == "x86_64" ]]; then
  cpu_template="T2S"
else
  cpu_template="None"
fi

start_agent() {
  local worker_id="$1"
  local agent_port="$2"
  local port_base="$3"

  env \
    FIREMIG_WORKER_ID="$worker_id" \
    FIREMIG_REGION="$worker_id" \
    FIREMIG_WORKDIR="$data_root/workers/$worker_id" \
    FIREMIG_AGENT_PORT="$agent_port" \
    FIREMIG_PORT_BASE="$port_base" \
    FIREMIG_AGENT_TOKEN="$FIREMIG_AGENT_TOKEN" \
    FIREMIG_PEER_URLS="worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102" \
    FIREMIG_SHARED_WORKER_ROOT="$data_root/workers" \
    FIREMIG_PROXY_HOST=127.0.0.1 \
    FIRECRACKER_BINARY="$assets/firecracker" \
    FIRECRACKER_VERSION=v1.16.1 \
    FIRECRACKER_SHA256="$firecracker_sha" \
    FIRECRACKER_SNAPSHOT_FORMAT=3.0.0 \
    FIREMIG_KERNEL="$assets/vmlinux-6.1.155" \
    FIREMIG_KERNEL_SHA256="$kernel_sha" \
    FIREMIG_ROOTFS="$assets/rootfs.ext4" \
    FIREMIG_CPU_TEMPLATE="$cpu_template" \
    FIREMIG_CPU_VENDOR="$cpu_vendor" \
    FIREMIG_CPU_MODEL="$cpu_model" \
    FIREMIG_CPU_FAMILY="$cpu_family" \
    FIREMIG_CPU_STEPPING="$cpu_stepping" \
    node /opt/firemig/packages/agent/dist/cli.js &
  pids+=("$!")
}

database_path="$data_root/coordinator/control.db"
DATABASE_PATH="$database_path" SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  "$coordinator" eval "FiremigCoordinator.Release.migrate()"

start_agent worker-a 4101 10000
start_agent worker-b 4102 20000

PROXY_TOKEN="$PROXY_TOKEN" ADMIN_PORT=4200 "$proxy" start &
pids+=("$!")

PHX_SERVER=true PORT=4000 PHX_HOST="${FIREMIG_PUBLIC_HOST:-127.0.0.1}" \
  DATABASE_PATH="$database_path" SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  API_TOKEN="$API_TOKEN" WORKER_TOKEN="$WORKER_TOKEN" PROXY_TOKEN="$PROXY_TOKEN" \
  REDPANDA_HTTP_URL="$REDPANDA_HTTP_URL" \
  PROXY_URL=http://127.0.0.1:4200 PROXY_PUBLIC_HOST="${FIREMIG_PUBLIC_HOST:-127.0.0.1}" \
  DEFAULT_PROXY_PORT=8080 \
  WORKER_URLS=worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102 \
  "$coordinator" start &
pids+=("$!")

for url in \
  http://127.0.0.1:4101/healthz \
  http://127.0.0.1:4102/healthz \
  http://127.0.0.1:4200/health \
  http://127.0.0.1:4000/healthz; do
  ready=0
  for _attempt in $(seq 1 120); do
    if curl -fsS --connect-timeout 1 --max-time 2 "$url" >/dev/null; then
      ready=1
      break
    fi
    sleep 0.25
  done
  if (( ready == 0 )); then
    echo "service did not become ready: $url" >&2
    exit 1
  fi
done

echo "firemig runtime ready"
wait -n "${pids[@]}"
