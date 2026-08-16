#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "remote-bootstrap must run as root" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  build-essential ca-certificates curl docker.io e2fsprogs git iproute2 jq make \
  linux-perf nftables openssl squashfs-tools util-linux xz-utils
systemctl enable --now docker

FIREMIG_DATA_ROOT=/var/lib/runable "$root/scripts/setup/preflight.sh"
image="hexpm/elixir:1.18.4-erlang-27.3.4.16-debian-bookworm-20260803-slim"
redpanda_image="docker.redpanda.com/redpandadata/redpanda:v25.2.7"

install_node() {
  if ! command -v node >/dev/null 2>&1 || [[ "$(node --version)" != v22.* ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  fi
  corepack enable
  corepack prepare pnpm@10.24.0 --activate
}

install_node &
node_pid=$!
"$root/scripts/setup/setup-assets.sh" &
assets_pid=$!
docker pull "$image" &
image_pid=$!
docker pull "$redpanda_image" &
redpanda_image_pid=$!

wait "$node_pid"
(
  pnpm --dir "$root" install --frozen-lockfile
  pnpm --dir "$root" build
) &
typescript_pid=$!

wait "$image_pid"

build_release() {
  local service="$1"
  docker run --rm \
    -v "$root:/src" \
    -w "/src/services/$service" \
    "$image" \
    bash -lc 'apt-get update >/dev/null && apt-get install -y build-essential git >/dev/null && mix local.hex --force && mix local.rebar --force && MIX_ENV=prod mix deps.get && MIX_ENV=prod mix compile --warnings-as-errors && MIX_ENV=prod mix release --overwrite'
}

build_release coordinator &
coordinator_pid=$!
build_release proxy &
proxy_pid=$!

wait "$assets_pid"
wait "$typescript_pid"
wait "$coordinator_pid"
wait "$proxy_pid"
wait "$redpanda_image_pid"
chmod +x "$root/scripts/runtime/remote-start.sh" "$root/scripts/local/down.sh" "$root/scripts/runtime/redpanda-runtime.sh"

echo "remote runtime built successfully"
