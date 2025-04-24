#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"

print_info "SSH Keyfiles – mounting SMB share with retry"

SMB_SERVER="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"
MAX_ATTEMPTS=3

mkdir -p "$TARGET_DIR"

# Attempt to mount up to MAX_ATTEMPTS times
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  print_info "Mount attempt $attempt/$MAX_ATTEMPTS"
  read -p "SMB Username: " SMB_USER
  read -s -p "SMB Password: " SMB_PASS
  echo ""

  # Use mount_smbfs (built-in) and pass password via stdin
  printf "%s\n" "$SMB_PASS" | mount_smbfs "//$SMB_USER@$SMB_SERVER" "$MOUNT_POINT" &>/dev/null
  if [[ $? -eq 0 && -d "$MOUNT_POINT" ]]; then
    print_success "SMB share mounted at $MOUNT_POINT"
    break
  else
    print_error "Mount failed. Please check your credentials or network."
    (( attempt++ ))
  fi
done

if [[ ! -d "$MOUNT_POINT" ]]; then
  print_error "Unable to mount SMB share after $MAX_ATTEMPTS attempts. Aborting."
  exit 1
fi

# Copy keys
print_info "Copying SSH key files to $TARGET_DIR"
cp "$MOUNT_POINT"/* "$TARGET_DIR"/ \
  && print_success "SSH keys copied" \
  || print_error "Failed to copy SSH keys"

# Unmount share
print_info "Unmounting $MOUNT_POINT"
if umount "$MOUNT_POINT" &>/dev/null; then
  print_success "Unmount successful"
else
  print_error "Failed to unmount $MOUNT_POINT"
fi

# Clean up
unset SMB_PASS
