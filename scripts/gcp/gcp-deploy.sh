#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tf_dir="$root/infra/gcp/environments/single-host"
gcloud_bin="${GCLOUD_BIN:-gcloud}"
project="${GCP_PROJECT_ID:-runable-505508}"

if ! command -v "$gcloud_bin" >/dev/null 2>&1 && [[ ! -x "$gcloud_bin" ]]; then
  echo "gcloud not found; set GCLOUD_BIN to the Google Cloud CLI executable" >&2
  exit 1
fi

instance_json="$(terraform -chdir="$tf_dir" output -json instance)"
instance="$(jq -r '.name' <<<"$instance_json")"
zone="$(jq -r '.zone' <<<"$instance_json")"
public_ip="$(jq -r '.public_ip' <<<"$instance_json")"
archive="$(mktemp -t runable-source.XXXXXX.tar.gz)"
remote_archive="/tmp/runable-source-$(date +%s)-$$.tar.gz"
trap 'rm -f "$archive"' EXIT

COPYFILE_DISABLE=1 tar --no-xattrs -czf "$archive" \
  --exclude=".git" --exclude="node_modules" --exclude="dist" --exclude="deps" \
  --exclude="_build" --exclude=".terraform" --exclude="*.tfstate*" \
  --exclude="runable-*.json" --exclude="assets/*" --exclude=".run" \
  -C "$root" .

"$gcloud_bin" compute scp "$archive" "$instance:$remote_archive" \
  --project="$project" --zone="$zone" --tunnel-through-iap --quiet

"$gcloud_bin" compute ssh "$instance" \
  --project="$project" --zone="$zone" --tunnel-through-iap --quiet \
  --command="set -e; if sudo test -x /opt/runable/scripts/local/down.sh; then sudo /opt/runable/scripts/local/down.sh; elif sudo test -x /opt/runable/scripts/down.sh; then sudo /opt/runable/scripts/down.sh; fi; sudo rm -rf /opt/runable && sudo mkdir -p /opt/runable && sudo tar -xzf $remote_archive -C /opt/runable && rm -f $remote_archive && sudo /opt/runable/scripts/runtime/remote-bootstrap.sh && sudo FIREMIG_PUBLIC_HOST=$public_ip /opt/runable/scripts/runtime/remote-start.sh && sudo cp /opt/runable/.run/runtime.env /tmp/runable-gcp.env && sudo chown \$(id -u):\$(id -g) /tmp/runable-gcp.env"

mkdir -p "$root/.run"
"$gcloud_bin" compute scp "$instance:/tmp/runable-gcp.env" "$root/.run/gcp.env" \
  --project="$project" --zone="$zone" --tunnel-through-iap --quiet
chmod 0600 "$root/.run/gcp.env"

set -a
source "$root/.run/gcp.env"
set +a
curl -fsS --retry 10 --retry-delay 2 "$FIREMIG_API_URL/healthz"
pnpm --dir "$root" build

if [[ "${PROFILE_MIGRATION:-0}" == "1" ]]; then
  "$gcloud_bin" compute ssh "$instance" \
    --project="$project" --zone="$zone" --tunnel-through-iap --quiet \
    --command="sudo bash -lc 'rm -f /tmp/firemig-perf.data /tmp/firemig-perf.log /tmp/firemig-perf.pid; nohup perf record -F 199 -a -g -o /tmp/firemig-perf.data -- sleep 120 >/tmp/firemig-perf.log 2>&1 & echo \$! >/tmp/firemig-perf.pid'"
fi

demo_status=0
pnpm --dir "$root" --filter @firemig/demo start || demo_status=$?

if [[ "${PROFILE_MIGRATION:-0}" == "1" ]]; then
  "$gcloud_bin" compute ssh "$instance" \
    --project="$project" --zone="$zone" --tunnel-through-iap --quiet \
    --command="sudo bash -lc 'kill -INT \$(cat /tmp/firemig-perf.pid) 2>/dev/null || true; for attempt in \$(seq 1 40); do kill -0 \$(cat /tmp/firemig-perf.pid) 2>/dev/null || break; sleep 0.25; done; test -d /opt/FlameGraph || git clone --depth 1 https://github.com/brendangregg/FlameGraph.git /opt/FlameGraph; perf script -i /tmp/firemig-perf.data 2>/tmp/firemig-perf-script.log | /opt/FlameGraph/stackcollapse-perf.pl | /opt/FlameGraph/flamegraph.pl --title \"Firecracker migration\" --subtitle \"snapshot, transfer, restore and cutover\" >/tmp/firemig-migration.svg; chmod 0644 /tmp/firemig-migration.svg'"
  mkdir -p "$root/flamegraphs"
  "$gcloud_bin" compute scp "$instance:/tmp/firemig-migration.svg" \
    "$root/flamegraphs/firemig-migration.svg" \
    --project="$project" --zone="$zone" --tunnel-through-iap --quiet
fi

exit "$demo_status"
