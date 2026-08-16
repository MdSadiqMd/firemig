#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="${GCP_PROJECT_ID:-runable-505508}"
credentials="${GOOGLE_APPLICATION_CREDENTIALS:?GOOGLE_APPLICATION_CREDENTIALS is required}"
gcloud_bin="${GCLOUD_BIN:-gcloud}"

if [[ "${CONFIRM_DESTROY:-}" != "$project" ]]; then
  echo "Refusing destructive operation. Set CONFIRM_DESTROY=$project" >&2
  exit 1
fi

GOOGLE_APPLICATION_CREDENTIALS="$credentials" \
  terraform -chdir="$root/infra/gcp/environments/single-host" destroy -input=false -auto-approve

"$gcloud_bin" storage rm --recursive "gs://${project}-firemig-tfstate/**" --quiet || true
GOOGLE_APPLICATION_CREDENTIALS="$credentials" \
  terraform -chdir="$root/infra/gcp/environments/bootstrap-state" destroy -input=false -auto-approve
