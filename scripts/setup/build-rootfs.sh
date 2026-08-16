#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
assets="${FIREMIG_ASSETS_DIR:-$root/assets}"
source_image="${1:-$assets/ubuntu-24.04.squashfs}"
output_image="${2:-$assets/rootfs.ext4}"
build_dir="$assets/rootfs-build"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ ! -f "$source_image" ]]; then
  echo "Rootfs source not found: $source_image" >&2
  exit 1
fi

rm -rf "$build_dir"
mkdir -p "$build_dir"
unsquashfs -d "$build_dir/root" "$source_image" >/dev/null

install -D -m 0755 "$root/guest/agent.py" "$build_dir/root/usr/local/lib/firemig/agent.py"
install -D -m 0644 "$root/guest/firemig-agent.service" "$build_dir/root/etc/systemd/system/firemig-agent.service"
mkdir -p "$build_dir/root/etc/systemd/system/multi-user.target.wants"
ln -sfn ../firemig-agent.service "$build_dir/root/etc/systemd/system/multi-user.target.wants/firemig-agent.service"

mkdir -p "$build_dir/root/opt/demo"
as_root chown -R root:root "$build_dir/root"
truncate -s "${FIREMIG_ROOTFS_SIZE:-1G}" "$output_image"
as_root mkfs.ext4 -q -F -d "$build_dir/root" "$output_image"
e2fsck -fn "$output_image" >/dev/null
rm -rf "$build_dir"
echo "built writable guest rootfs: $output_image"
