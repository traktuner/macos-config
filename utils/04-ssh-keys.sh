#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles – mounting SMB share via Finder and copying keys"

SMB_PATH="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"
TIMEOUT=30   # seconds to wait for mount

# Prompt for credentials
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo

# Ensure target folder exists
ensure_directory "$TARGET_DIR" false

# If already mounted, unmount first
if mount | grep -q "on $MOUNT_POINT "; then
  print_info "Unmounting existing share…"
  sudo diskutil unmount "$MOUNT_POINT" &>/dev/null \
    && print_success "Existing share unmounted" \
    || print_error "Failed to unmount existing share"
fi

# Trigger Finder mount (opens credentials dialog)
print_info "Opening Finder to mount smb://…"
open "smb://$SMB_USER:$SMB_PASS@$SMB_PATH"

# Wait for the mount to appear
print_info "Waiting up to $TIMEOUT seconds for $MOUNT_POINT to appear…"
elapsed=0
while (( elapsed < TIMEOUT )); do
  if [[ -d "$MOUNT_POINT" ]]; then
    print_success "SMB share mounted at $MOUNT_POINT"
    break
  fi
  sleep 1
  (( elapsed++ ))
done

if [[ ! -d "$MOUNT_POINT" ]]; then
  print_error "Mount did not appear within $TIMEOUT seconds. Aborting."
  unset SMB_PASS
  exit 1
fi

# Copy SSH keys
print_info "Copying SSH keys to $TARGET_DIR…"
if sudo cp -R "$MOUNT_POINT"/* "$TARGET_DIR"/; then
  print_success "SSH keys copied"
else
  print_error "Failed to copy SSH keys"
fi

# Unmount when done
print_info "Unmounting $MOUNT_POINT…"
if sudo diskutil unmount "$MOUNT_POINT"; then
  print_success "Unmounted share"
else
  print_error "Failed to unmount share"
fi

# Clean up
unset SMB_PASS
