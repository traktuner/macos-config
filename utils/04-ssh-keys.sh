#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles – mounting SMB share and copying keys"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
SMB_SERVER="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"        # ← hier sicher definieren
MAX_ATTEMPTS=3

# ─────────────────────────────────────────────────────────────────────────────
# Prompt for credentials
# ─────────────────────────────────────────────────────────────────────────────
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo

# ─────────────────────────────────────────────────────────────────────────────
# Prepare mount point and target dir
# ─────────────────────────────────────────────────────────────────────────────
ensure_directory "$TARGET_DIR" false
ensure_directory "$MOUNT_POINT" true

# ─────────────────────────────────────────────────────────────────────────────
# Unmount stale mount if present
# ─────────────────────────────────────────────────────────────────────────────
if mount | grep -q "on $MOUNT_POINT "; then
  print_info "Unmounting stale share…"
  sudo diskutil unmount "$MOUNT_POINT" &>/dev/null \
    && print_success "Stale share unmounted" \
    || print_error "Failed to unmount stale share"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Attempt to mount via mount_smbfs
# ─────────────────────────────────────────────────────────────────────────────
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  print_info "Mount attempt $attempt/$MAX_ATTEMPTS"
  # feed password via stdin, use sudo so we own the mount
  if printf "%s\n" "$SMB_PASS" | sudo mount_smbfs "//$SMB_USER@$SMB_SERVER" "$MOUNT_POINT"; then
    print_success "SMB share mounted at $MOUNT_POINT"
    break
  else
    print_error "Mount failed"
    (( attempt++ ))
    sleep 2
  fi
done

if (( attempt > MAX_ATTEMPTS )); then
  print_error "Could not mount SMB share after $MAX_ATTEMPTS attempts"
  unset SMB_PASS
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Copy SSH keys as root
# ─────────────────────────────────────────────────────────────────────────────
print_info "Copying SSH keys to $TARGET_DIR…"
if sudo cp -R "$MOUNT_POINT"/* "$TARGET_DIR"/; then
  print_success "SSH keys copied"
else
  print_error "Failed to copy SSH keys"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Unmount share
# ─────────────────────────────────────────────────────────────────────────────
print_info "Unmounting $MOUNT_POINT…"
if sudo diskutil unmount "$MOUNT_POINT"; then
  print_success "Unmounted share"
else
  print_error "Failed to unmount share"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Clean up sensitive data
# ─────────────────────────────────────────────────────────────────────────────
unset SMB_PASS
