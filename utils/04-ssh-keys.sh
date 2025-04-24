#!/usr/bin/env bash
set -euo pipefail

# Load our helper functions
source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles setup"

SMB_PATH="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"

# 1) Prompt for credentials
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo ""

# 2) Prepare target folder
ensure_directory "$TARGET_DIR" false

# 3) Clean up any stale mount
if mount | grep -q "on $MOUNT_POINT "; then
  print_info "Unmounting stale share at $MOUNT_POINT…"
  sudo diskutil unmount "$MOUNT_POINT" &>/dev/null \
    && print_success "Stale share unmounted" \
    || print_error "Failed to unmount stale share"
fi

# 4) Trigger Finder mount
print_info "Mounting SMB share via Finder…"
if open "smb://$SMB_USER:$SMB_PASS@$SMB_PATH"; then
  # wait up to 10s for the volume to appear
  for i in {1..10}; do
    [[ -d "$MOUNT_POINT" ]] && break
    sleep 1
  done

  if [[ -d "$MOUNT_POINT" ]]; then
    print_success "SMB share mounted at $MOUNT_POINT"

    # 5) Copy SSH keys as root
    print_info "Copying SSH keys to $TARGET_DIR…"
    if sudo cp -R "$MOUNT_POINT"/* "$TARGET_DIR"/; then
      print_success "SSH keys copied"
    else
      print_error "Failed to copy SSH keys"
    fi

    # 6) Unmount
    print_info "Unmounting $MOUNT_POINT…"
    if sudo diskutil unmount "$MOUNT_POINT"; then
      print_success "Unmounted share"
    else
      print_error "Failed to unmount share"
    fi
  else
    print_error "Mount failed: $MOUNT_POINT did not appear"
    exit 1
  fi
else
  print_error "Could not invoke Finder mount (open smb://…)"
  exit 1
fi

# 7) Cleanup sensitive data
unset SMB_PASS
