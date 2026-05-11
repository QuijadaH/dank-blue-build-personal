#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi   

if ! blkid -L WD-1TB >/dev/null; then
  echo "Filesystem label WD-1TB not found."
  exit 1
fi

FSTAB="/etc/fstab"
cp "$FSTAB" "${FSTAB}.bak.$(date +%F-%H%M%S)"

SAMSUNG_UUID=$(findmnt -n -o UUID /var)
TEMP_MOUNTPOINT=$(mktemp -d -p /tmp mnt.XXXXXX)
mount -o subvolid=5 UUID=${SAMSUNG_UUID} ${TEMP_MOUNTPOINT}
trap 'umount "$TEMP_MOUNTPOINT" &>/dev/null || true; rmdir "$TEMP_MOUNTPOINT" &>/dev/null || true' EXIT   

if btrfs subvolume show "${TEMP_MOUNTPOINT}"/storage &> /dev/null; then
    echo "Btrfs subvolume '/storage' already exists in UUID ${SAMSUNG_UUID}."
else
    echo "Creating Btrfs subvolume '/storage' in UUID ${SAMSUNG_UUID}..."
    btrfs subvolume create ${TEMP_MOUNTPOINT}/storage
fi

umount "${TEMP_MOUNTPOINT}"
rmdir "${TEMP_MOUNTPOINT}"

mkdir -p /var/mnt/WD-1TB@FILES
mkdir -p /var/mnt/WD-1TB@SEEDS
mkdir -p /var/mnt/WD-1TB@STEAM
mkdir -p /var/mnt/SAMSUNG@STORAGE

ENTRIES=(
"LABEL=WD-1TB  /var/mnt/WD-1TB@FILES  btrfs  subvol=/@files,noatime,X-mount.mkdir,compress=zstd:3,autodefrag,space_cache=v2  0 0"
"LABEL=WD-1TB  /var/mnt/WD-1TB@SEEDS  btrfs  subvol=/@seeds,noatime,X-mount.mkdir,compress=zstd:3,autodefrag,space_cache=v2  0 0"
"LABEL=WD-1TB  /var/mnt/WD-1TB@STEAM  btrfs  subvol=/@steam,noatime,X-mount.mkdir,autodefrag,space_cache=v2  0 0"
"UUID=${SAMSUNG_UUID}  /var/mnt/SAMSUNG@STORAGE  btrfs  subvol=/storage,noatime,X-mount.mkdir,ssd,discard=async,space_cache=v2  0 0"
)

for entry in "${ENTRIES[@]}"; do
  if grep -Fxq -- "$entry" "$FSTAB"; then
    echo "Skipping (already exists): $entry"
  else
    echo "$entry" >> "$FSTAB"
    echo "Added: $entry"
  fi
done

echo "Validating fstab..."
mount -a

echo "Done updating /etc/fstab"