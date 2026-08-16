#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
assets="${FIREMIG_ASSETS_DIR:-$root/assets}"
firecracker_version="v1.16.1"
architecture="${FIREMIG_ARCHITECTURE:-$(uname -m)}"

case "$architecture" in
  amd64|x86_64)
    architecture="x86_64"
    firecracker_sha256="382a02a869e4d6d5cb14c40577f9545e8458021ea8b0b2d3fc10ec14d9c242e6"
    ;;
  arm64|aarch64)
    architecture="aarch64"
    firecracker_sha256="8d0e69f6d6f9a1724551f607f18504052c16c1828ee3d4d7b6e6c73380871e0e"
    ;;
  *)
    echo "Unsupported Firecracker architecture: $architecture" >&2
    exit 1
    ;;
esac

firecracker_archive="firecracker-${firecracker_version}-${architecture}.tgz"
firecracker_url="https://github.com/firecracker-microvm/firecracker/releases/download/${firecracker_version}/${firecracker_archive}"
kernel_key="firecracker-ci/v1.15/${architecture}/vmlinux-6.1.155"
rootfs_key="firecracker-ci/v1.15/${architecture}/ubuntu-24.04.squashfs"
kernel_url="https://s3.amazonaws.com/spec.ccfc.min/${kernel_key}"
rootfs_url="https://s3.amazonaws.com/spec.ccfc.min/${rootfs_key}"

mkdir -p "$assets"
archive_path="$assets/$firecracker_archive"
kernel_source="$assets/vmlinux-6.1.155-$architecture"
rootfs_source="$assets/ubuntu-24.04-$architecture.squashfs"

download() {
  local url="$1"
  local destination="$2"
  if [[ -f "$destination" ]]; then
    return
  fi
  curl --fail --location --retry 5 --retry-all-errors --connect-timeout 15 \
    --output "$destination.partial" "$url"
  mv "$destination.partial" "$destination"
}

download "$firecracker_url" "$archive_path" &
firecracker_download_pid=$!
download "$kernel_url" "$kernel_source" &
kernel_download_pid=$!
download "$rootfs_url" "$rootfs_source" &
rootfs_download_pid=$!

wait "$firecracker_download_pid"
wait "$kernel_download_pid"
wait "$rootfs_download_pid"

actual_firecracker_sha256="$(sha256sum "$archive_path" | cut -d ' ' -f 1)"
if [[ "$actual_firecracker_sha256" != "$firecracker_sha256" ]]; then
  echo "Firecracker archive digest mismatch" >&2
  exit 1
fi

rm -rf "$assets/release-${firecracker_version}-${architecture}"
tar -xzf "$archive_path" -C "$assets"
install -m 0755 \
  "$assets/release-${firecracker_version}-${architecture}/firecracker-${firecracker_version}-${architecture}" \
  "$assets/firecracker"
install -m 0644 "$kernel_source" "$assets/vmlinux-6.1.155"

"$root/scripts/setup/build-rootfs.sh" "$rootfs_source" "$assets/rootfs.ext4"

kernel_sha256="$(sha256sum "$assets/vmlinux-6.1.155" | cut -d ' ' -f 1)"
rootfs_source_sha256="$(sha256sum "$rootfs_source" | cut -d ' ' -f 1)"
rootfs_sha256="$(sha256sum "$assets/rootfs.ext4" | cut -d ' ' -f 1)"

cat >"$assets/MANIFEST.json" <<EOF
{
  "firecracker": {
    "version": "$firecracker_version",
    "architecture": "$architecture",
    "url": "$firecracker_url",
    "sha256": "$firecracker_sha256"
  },
  "kernel": {
    "key": "$kernel_key",
    "url": "$kernel_url",
    "sha256": "$kernel_sha256"
  },
  "rootfsSource": {
    "key": "$rootfs_key",
    "url": "$rootfs_url",
    "sha256": "$rootfs_source_sha256"
  },
  "rootfs": {
    "path": "rootfs.ext4",
    "sha256": "$rootfs_sha256"
  }
}
EOF

echo "assets ready in $assets"
