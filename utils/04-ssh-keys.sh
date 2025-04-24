#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles – mounting SMB share and copying keys"

# --- Configuration ---
SMB_PATH="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
# Define TARGET_DIR here to avoid unbound-variable
TARGET_DIR="${TARGET_DIR:-$HOME/.ssh}"
MAX_ATTEMPTS=3

# --- Prompt for credentials ---
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo ""

# --- Prepare folders ---
ensure_directory "$TARGET_DIR" false
ensure_directory "$MOUNT_POINT" true

# --- Unmount stale mount, if any ---
if mount | grep -q "on $MOUNT_POINT "; then
  print_info "Unmounting stale share at $MOUNT_POINT…"
  sudo diskutil unmount "$MOUNT_POINT" &>/dev/null \
    && print_success "Stale share unmounted" \
    || print_error "Failed to unmount stale share"
fi

# --- Attempt to mount via Finder (open smb://…) ---
print_info "Mounting SMB share via Finder…"
if ! open "smb://$SMB_USER:$SMB_PASS@$SMB_PATH"; then
  print_error "Failed to invoke Finder for smb:// mount"
  exit 1
fi

# wait up to 10s for volume to appear
for i in {1..10}; do
  [[ -d "$MOUNT_POINT" ]] && break
  sleep 1
done

if [[ ! -d "$MOUNT_POINT" ]]; then
  print_error "Mount failed: $MOUNT_POINT did not appear"
  exit 1
fi
print_success "SMB share mounted at $MOUNT_POINT"

# --- Copy SSH keys as root ---
print_info "Copying SSH keys to $TARGET_DIR…"
if sudo cp -R "$MOUNT_POINT"/* "$TARGET_DIR"/; then
  print_success "SSH keys copied"
else
  print_error "Failed to copy SSH keys"
fi

# --- Unmount share ---
print_info "Unmounting $MOUNT_POINT…"
if sudo diskutil unmount "$MOUNT_POINT"; then
  print_success "Unmounted share"
else
  print_error "Failed to unmount share"
fi

# --- Clean up sensitive data ---
unset SMB_PASS
