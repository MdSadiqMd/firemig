#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
run_dir="$root/.run"
env_file="$run_dir/runtime.env"
public_host="${FIREMIG_PUBLIC_HOST:-127.0.0.1}"
lima_instance="${FIREMIG_LIMA_INSTANCE:-firemig-kvm}"
docker_context="${FIREMIG_DOCKER_CONTEXT:-lima-${lima_instance}}"
export FIREMIG_PUBLIC_HOST="$public_host"

if ! command -v limactl >/dev/null 2>&1; then
  echo "Lima is required; install it with: brew install lima" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "The Docker CLI is required" >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required" >&2
  exit 1
fi

lima_status="$(limactl list "$lima_instance" --format '{{.Status}}' 2>/dev/null || true)"
if [[ -z "$lima_status" ]]; then
  limactl start \
    --name="$lima_instance" \
    --vm-type=vz \
    --nested-virt \
    --cpus="${FIREMIG_LIMA_CPUS:-8}" \
    --memory="${FIREMIG_LIMA_MEMORY_GIB:-16}" \
    --disk="${FIREMIG_LIMA_DISK_GIB:-100}" \
    --port-forward=4000:4000,static=true \
    --port-forward=8080:8080,static=true \
    --tty=false \
    template:docker-rootful
elif [[ "$lima_status" != "Running" ]]; then
  limactl start "$lima_instance" --tty=false
fi

docker_endpoint="$(limactl list "$lima_instance" --format 'unix://{{.Dir}}/sock/docker.sock')"
if docker context inspect "$docker_context" >/dev/null 2>&1; then
  current_endpoint="$(docker context inspect "$docker_context" --format '{{.Endpoints.docker.Host}}')"
  if [[ "$current_endpoint" != "$docker_endpoint" ]]; then
    docker context update "$docker_context" --docker "host=$docker_endpoint" >/dev/null
  fi
else
  docker context create "$docker_context" --docker "host=$docker_endpoint" >/dev/null
fi
docker context use "$docker_context" >/dev/null

if ! docker info >/dev/null 2>&1; then
  echo "Docker in Lima instance $lima_instance is not reachable" >&2
  exit 1
fi

mkdir -p "$run_dir"
chmod 0700 "$run_dir"

if [[ -f "$env_file" ]]; then
  set -a
  source "$env_file"
  set +a
fi

agent_token="${FIREMIG_AGENT_TOKEN:-${WORKER_TOKEN:-$(openssl rand -hex 32)}}"
proxy_token="${PROXY_TOKEN:-$(openssl rand -hex 32)}"
api_token="${FIREMIG_API_TOKEN:-${API_TOKEN:-$(openssl rand -hex 32)}}"
secret_key_base="${SECRET_KEY_BASE:-$(openssl rand -base64 64 | tr -d '\n')}"
cat >"$env_file" <<EOF
FIREMIG_API_URL=http://${public_host}:4000
FIREMIG_API_TOKEN=${api_token}
API_TOKEN=${api_token}
WORKER_TOKEN=${agent_token}
FIREMIG_AGENT_TOKEN=${agent_token}
PROXY_TOKEN=${proxy_token}
SECRET_KEY_BASE=${secret_key_base}
REDPANDA_HTTP_URL=http://redpanda:8082
EOF
chmod 0600 "$env_file"

docker compose --project-directory "$root" up --build --detach --wait --wait-timeout 900

if ! docker compose --project-directory "$root" exec -T runtime test -c /dev/kvm; then
  echo "Warning: Docker does not expose /dev/kvm; the API is ready, but Firecracker VM creation requires a KVM-capable Docker engine." >&2
fi

echo "firemig is ready: http://${public_host}:4000"

if [[ "${FIREMIG_FOLLOW_LOGS:-1}" == "1" ]]; then
  echo "following runtime logs; press Ctrl-C to detach"
  docker compose --project-directory "$root" logs -f --tail="${FIREMIG_LOG_TAIL:-100}" runtime
fi
