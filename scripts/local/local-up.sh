#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
run_dir="$root/.run"
assets="$root/assets"
data_root="${FIREMIG_DATA_ROOT:-/var/lib/firemig}"

source "$root/scripts/runtime/redpanda-runtime.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "local-up must run as root to create network and mount namespaces" >&2
  exit 1
fi

for path in "$assets/firecracker" "$assets/vmlinux-6.1.155" "$assets/rootfs.ext4" "$assets/MANIFEST.json"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing asset $path; run make setup first" >&2
    exit 1
  fi
done

mkdir -p "$run_dir" "$run_dir/logs" "$data_root/workers/worker-a" "$data_root/workers/worker-b" "$data_root/coordinator"
chmod 0700 "$run_dir"

if [[ ! -f "$run_dir/runtime.env" ]]; then
  agent_token="$(openssl rand -hex 32)"
  proxy_token="$(openssl rand -hex 32)"
  api_token="$(openssl rand -hex 32)"
  secret_key_base="$(openssl rand -base64 64 | tr -d '\n')"
  public_host="${FIREMIG_PUBLIC_HOST:-127.0.0.1}"
  cat >"$run_dir/runtime.env" <<EOF
FIREMIG_API_URL=http://${public_host}:4000
FIREMIG_API_TOKEN=${api_token}
API_TOKEN=${api_token}
WORKER_TOKEN=${agent_token}
FIREMIG_AGENT_TOKEN=${agent_token}
PROXY_TOKEN=${proxy_token}
SECRET_KEY_BASE=${secret_key_base}
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
cpu_vendor="$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
cpu_model="$(lscpu | awk -F: '/Model name/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
cpu_family="$(lscpu | awk -F: '/CPU family/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
cpu_stepping="$(lscpu | awk -F: '/Stepping/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is required to start Redpanda before the local runtime" >&2
  exit 1
fi
start_redpanda "$data_root/redpanda"

start_process() {
  local name="$1"
  shift
  if [[ -f "$run_dir/$name.pid" ]] && kill -0 "$(cat "$run_dir/$name.pid")" 2>/dev/null; then
    echo "$name is already running"
    return
  fi
  nohup "$@" >"$run_dir/logs/$name.log" 2>&1 &
  echo "$!" >"$run_dir/$name.pid"
}

common_agent_env=(
  env
  FIRECRACKER_BINARY="$assets/firecracker"
  FIRECRACKER_VERSION="v1.16.1"
  FIRECRACKER_SHA256="$firecracker_sha"
  FIRECRACKER_SNAPSHOT_FORMAT="3.0.0"
  FIREMIG_KERNEL="$assets/vmlinux-6.1.155"
  FIREMIG_KERNEL_SHA256="$kernel_sha"
  FIREMIG_ROOTFS="$assets/rootfs.ext4"
  FIREMIG_CPU_VENDOR="$cpu_vendor"
  FIREMIG_CPU_MODEL="$cpu_model"
  FIREMIG_CPU_FAMILY="$cpu_family"
  FIREMIG_CPU_STEPPING="$cpu_stepping"
  FIREMIG_CPU_TEMPLATE="T2S"
  FIREMIG_PROXY_HOST="127.0.0.1"
  FIREMIG_PEER_URLS="worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102"
  FIREMIG_AGENT_TOKEN="$FIREMIG_AGENT_TOKEN"
)

start_process worker-a "${common_agent_env[@]}" \
  FIREMIG_WORKER_ID=worker-a FIREMIG_REGION=worker-a \
  FIREMIG_WORKDIR="$data_root/workers/worker-a" FIREMIG_PORT_BASE=10000 \
  FIREMIG_AGENT_PORT=4101 node "$root/packages/agent/dist/cli.js"

start_process worker-b "${common_agent_env[@]}" \
  FIREMIG_WORKER_ID=worker-b FIREMIG_REGION=worker-b \
  FIREMIG_WORKDIR="$data_root/workers/worker-b" FIREMIG_PORT_BASE=20000 \
  FIREMIG_AGENT_PORT=4102 node "$root/packages/agent/dist/cli.js"

start_process proxy env MIX_ENV=prod ADMIN_PORT=4200 PROXY_TOKEN="$PROXY_TOKEN" \
  bash -lc "cd '$root/services/proxy' && exec mix run --no-halt"

(
  cd "$root/services/coordinator"
  MIX_ENV=prod DATABASE_PATH="$data_root/coordinator/control.db" \
    SECRET_KEY_BASE="$SECRET_KEY_BASE" mix ecto.create --quiet
  MIX_ENV=prod DATABASE_PATH="$data_root/coordinator/control.db" \
    SECRET_KEY_BASE="$SECRET_KEY_BASE" mix ecto.migrate --quiet
)

start_process coordinator env MIX_ENV=prod PHX_SERVER=true PORT=4000 \
  DATABASE_PATH="$data_root/coordinator/control.db" SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  API_TOKEN="$API_TOKEN" WORKER_TOKEN="$WORKER_TOKEN" PROXY_TOKEN="$PROXY_TOKEN" \
  REDPANDA_HTTP_URL="$REDPANDA_HTTP_URL" \
  PROXY_URL=http://127.0.0.1:4200 PROXY_PUBLIC_HOST="${FIREMIG_PUBLIC_HOST:-127.0.0.1}" \
  DEFAULT_PROXY_PORT=8080 \
  WORKER_URLS=worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102 \
  bash -lc "cd '$root/services/coordinator' && exec mix phx.server"

for url in http://127.0.0.1:4101/healthz http://127.0.0.1:4102/healthz http://127.0.0.1:4200/health http://127.0.0.1:4000/healthz; do
  for _attempt in $(seq 1 60); do
    if curl -fsS --connect-timeout 1 --max-time 2 "$url" >/dev/null; then
      break
    fi
    sleep 0.25
  done
  curl -fsS --connect-timeout 1 --max-time 2 "$url" >/dev/null
done

echo "firemig is ready: ${FIREMIG_API_URL}"
