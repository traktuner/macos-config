#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"

print_info "SSH Keyfiles – mounting SMB share with retry"

SMB_SERVER="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"
MAX_ATTEMPTS=3

# 1) Ensure the ~/.ssh folder exists
mkdir -p "$TARGET_DIR"

# 2) Prepare the mount point
if [[ ! -d "$MOUNT_POINT" ]]; then
  print_info "Creating mount point $MOUNT_POINT…"
  sudo mkdir -p "$MOUNT_POINT" \
    && print_success "Created mount point" \
    || { print_error "Failed to create mount point"; exit 1; }
fi

# If already mounted, unmount first
if mount | grep -q "on $MOUNT_POINT "; then
  print_info "Stale mount found—unmounting first…"
  sudo umount "$MOUNT_POINT" \
    && print_success "Unmounted stale volume" \
    || print_error "Failed to unmount stale volume"
fi

# 3) Try to mount up to MAX_ATTEMPTS times
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  print_info "Mount attempt $attempt/$MAX_ATTEMPTS"
  read -p "SMB Username: " SMB_USER
  read -s -p "SMB Password: " SMB_PASS
  echo ""

  # Try mounting (redirect stderr so we can show the error on failure)
  sudo mount_smbfs "//$SMB_USER:$SMB_PASS@$SMB_SERVER" "$MOUNT_POINT" 2>"/tmp/smb-mount-error.log"
  rc=$?

  if (( rc == 0 )); then
    print_success "SMB share mounted at $MOUNT_POINT"
    break
  else
    err=$(<"/tmp/smb-mount-error.log")
    print_error "Mount failed (exit code $rc): $err"
    (( attempt++ ))
  fi
done

if (( attempt > MAX_ATTEMPTS )); then
  print_error "Unable to mount SMB share after $MAX_ATTEMPTS attempts. Aborting."
  exit 1
fi

# 4) Copy keys
print_info "Copying SSH key files to $TARGET_DIR"
cp "$MOUNT_POINT"/* "$TARGET_DIR"/ \
  && print_success "SSH keys copied" \
  || print_error "Failed to copy SSH keys"

# 5) Unmount
print_info "Unmounting $MOUNT_POINT"
if sudo umount "$MOUNT_POINT"; then
  print_success "Unmount successful"
else
  print_error "Failed to unmount $MOUNT_POINT"
fi

# Clean up
unset SMB_PASS
