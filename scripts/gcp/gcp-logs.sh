#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tf_dir="$root/infra/gcp/environments/single-host"
gcloud_bin="${GCLOUD_BIN:-gcloud}"
project="${GCP_PROJECT_ID:-runable-505508}"
instance_json="$(terraform -chdir="$tf_dir" output -json instance)"
instance="$(jq -r '.name' <<<"$instance_json")"
zone="$(jq -r '.zone' <<<"$instance_json")"

"$gcloud_bin" compute ssh "$instance" \
  --project="$project" --zone="$zone" --tunnel-through-iap --quiet \
  --command="sudo bash -s" <<'REMOTE'
set -u

follow() {
  name=$1
  shift
  "$@" | sed "s/^/[${name}] /" &
}

echo STATUS
ss -ltnp | grep -E "4000|4101|4102|4200|8080|8082|9092|9644" || true
echo HEALTH
curl -fsS http://127.0.0.1:4000/healthz || true
echo
curl -fsS http://127.0.0.1:4200/health || true
echo
echo REDPANDA
docker ps -a --filter name=^/firemig-redpanda$ --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
docker inspect --format "health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" firemig-redpanda 2>/dev/null || true
curl -fsS http://127.0.0.1:8082/brokers || true
echo
echo "LIVE LOGS (ctrl-c to stop)"
follow REDPANDA docker logs --tail 20 --follow firemig-redpanda 2>&1
follow WORKER_A tail -n 20 -f /opt/runable/.run/logs/worker-a.log 2>/dev/null
follow WORKER_B tail -n 20 -f /opt/runable/.run/logs/worker-b.log 2>/dev/null
follow STARTUP journalctl -u google-startup-scripts.service -n 20 -f
wait
REMOTE
