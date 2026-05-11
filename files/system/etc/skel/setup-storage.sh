#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi   

FSTAB="/etc/fstab"
cp "$FSTAB" "${FSTAB}.bak.$(date +%F-%H%M%S)"

WD_1TB_SUCCESS=false
SAMSUNG_SUCCESS=false

if ! blkid -L "WD-1TB" >/dev/null 2>&1; then
  echo "Cannot find WD-1TB. Skipping entries for WD-1TB."
else
  mkdir -p /var/mnt/WD-1TB@FILES
  mkdir -p /var/mnt/WD-1TB@SEEDS
  mkdir -p /var/mnt/WD-1TB@STEAM

  ENTRIES=(
  "LABEL=WD-1TB  /var/mnt/WD-1TB@FILES  btrfs  subvol=/@files,noatime,X-mount.mkdir,compress=zstd:3,autodefrag,space_cache=v2  0 0"
  "LABEL=WD-1TB  /var/mnt/WD-1TB@SEEDS  btrfs  subvol=/@seeds,noatime,X-mount.mkdir,compress=zstd:3,autodefrag,space_cache=v2  0 0"
  "LABEL=WD-1TB  /var/mnt/WD-1TB@STEAM  btrfs  subvol=/@steam,noatime,X-mount.mkdir,autodefrag,space_cache=v2  0 0"
  )

  for entry in "${ENTRIES[@]}"; do
    device=$(awk '{print $1}' <<< "$entry")
    mountpoint=$(awk '{print $2}' <<< "$entry")

    if grep -Eq "^${device}[[:space:]]+${mountpoint}[[:space:]]" "$FSTAB"; then
      echo "'${device} ${mountpoint}' already exists in $FSTAB"
    else
      echo "$entry" >> "$FSTAB"
    fi
  done

  WD_1TB_SUCCESS=true
fi

if findmnt -t btrfs /var >/dev/null 2>&1; then   
	SAMSUNG_UUID=$(findmnt -no UUID -T /var)
  TEMP_MOUNTPOINT=$(mktemp -d)
  mount -o subvolid=5 UUID=${SAMSUNG_UUID} ${TEMP_MOUNTPOINT}
  cleanup() {
    umount "$TEMP_MOUNTPOINT" 2>/dev/null || true
    rmdir "$TEMP_MOUNTPOINT" 2>/dev/null || true
  }
  trap cleanup EXIT   

  if btrfs subvolume list "$TEMP_MOUNTPOINT"  | awk '{print $NF}' | grep -qx "storage"; then
    echo "Btrfs subvolume '/storage' already exists in UUID ${SAMSUNG_UUID}."
  else
    echo "Creating Btrfs subvolume '/storage' in UUID ${SAMSUNG_UUID}..."
    btrfs subvolume create "${TEMP_MOUNTPOINT}/storage"
  fi

  mkdir -p /var/mnt/SAMSUNG@STORAGE
  SAMSUNG_ENTRY="UUID=${SAMSUNG_UUID}  /var/mnt/SAMSUNG@STORAGE  btrfs  subvol=/storage,noatime,X-mount.mkdir,ssd,discard=async,space_cache=v2  0 0"

  device=$(awk '{print $1}' <<< "$SAMSUNG_ENTRY")
  mountpoint=$(awk '{print $2}' <<< "$SAMSUNG_ENTRY")

  if grep -Eq "^${device}[[:space:]]+${mountpoint}[[:space:]]" "$FSTAB"; then
    echo "'${device} ${mountpoint}' already exists in $FSTAB"
  else
    echo "$SAMSUNG_ENTRY" >> "$FSTAB"
  fi
  
  SAMSUNG_SUCCESS=true
else
  echo "Cannot find or create the storage subvolume for the Samsung drive. Skipping entry for the Samsung drive."
fi	

if [[ "$WD_1TB_SUCCESS" == true ]] || [[ "$SAMSUNG_SUCCESS" == true ]]; then
  echo "Done updating /etc/fstab."
  echo "Validating new mounts..."

  if [[ "$WD_1TB_SUCCESS" == true ]]; then
    if ! mount /var/mnt/WD-1TB@FILES; then
      echo "Failed to mount /var/mnt/WD-1TB@FILES" >&2
      exit 1
    fi

    if ! mount /var/mnt/WD-1TB@SEEDS; then
      echo "Failed to mount /var/mnt/WD-1TB@SEEDS" >&2
      exit 1
    fi

    if ! mount /var/mnt/WD-1TB@STEAM; then
      echo "Failed to mount /var/mnt/WD-1TB@STEAM" >&2
      exit 1
    fi
  fi

  if [[ "$SAMSUNG_SUCCESS" == true ]]; then
    if ! mount /var/mnt/SAMSUNG@STORAGE; then
      echo "Failed to mount /var/mnt/SAMSUNG@STORAGE" >&2
      exit 1
    fi
  fi
else
  echo "No entries were added to /etc/fstab."
fi

exit 0