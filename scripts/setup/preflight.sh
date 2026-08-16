#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Firecracker setup requires Linux; detected $(uname -s)." >&2
  exit 1
fi

if [[ ! -c /dev/kvm || ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "/dev/kvm must exist and be readable and writable by the current user." >&2
  exit 1
fi

kernel="$(uname -r)"
case "$kernel" in
  5.10.*|6.1.*|6.18.*) ;;
  *)
    echo "Host kernel $kernel is outside the tested Firecracker compatibility set: 5.10, 6.1, 6.18." >&2
    exit 1
    ;;
esac

for command in curl tar sha256sum unsquashfs truncate mkfs.ext4 e2fsck ip nft nsenter unshare; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is missing: $command" >&2
    exit 1
  fi
done

available_kib="$(df -Pk "${FIREMIG_DATA_ROOT:-/var/lib/firemig}" | awk 'NR == 2 {print $4}')"
required_kib="${FIREMIG_REQUIRED_FREE_KIB:-8388608}"
if (( available_kib < required_kib )); then
  echo "Insufficient free space: ${available_kib} KiB available, ${required_kib} KiB required." >&2
  exit 1
fi

echo "preflight ok: kernel=$kernel kvm=/dev/kvm free_kib=$available_kib"
