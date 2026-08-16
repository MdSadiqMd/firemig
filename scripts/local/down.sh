#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
run_dir="$root/.run"

for name in coordinator proxy worker-b worker-a; do
  pid_file="$run_dir/$name.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
done

pkill -TERM -f "$root/assets/firecracker --api-sock" 2>/dev/null || true

if command -v docker >/dev/null 2>&1 && docker container inspect firemig-redpanda >/dev/null 2>&1; then
  docker stop firemig-redpanda >/dev/null
fi

for namespace in $(ip netns list | awk '/^fm/ {print $1}'); do
  namespace_pids="$(ip netns pids "$namespace")"
  if [[ -n "$namespace_pids" ]]; then
    kill $namespace_pids 2>/dev/null || true
  fi
  ip netns delete "$namespace" 2>/dev/null || true
done

echo "firemig processes, Redpanda and network namespaces stopped"
