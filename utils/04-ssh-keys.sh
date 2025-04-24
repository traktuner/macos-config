#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles"

SMB_PATH="//172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_FOLDER="$HOME/.ssh"
MAX_ATTEMPTS=3

# 1) Prompt for credentials
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo ""

# 2) Ensure mount point and target exist
ensure_directory "$MOUNT_POINT" true
ensure_directory "$TARGET_FOLDER" false

# 3) Attempt to mount via mount_smbfs up to MAX_ATTEMPTS
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  print_info "Mount attempt $attempt/$MAX_ATTEMPTS"
  # use sudo so we own the volume
  if printf "%s\n" "$SMB_PASS" | sudo mount_smbfs "$SMB_USER@$SMB_PATH" "$MOUNT_POINT" &>/tmp/smb.log; then
    print_success "SMB share mounted at $MOUNT_POINT"
    break
  else
    print_error "Mount failed: $(< /tmp/smb.log | tail -1)"
    (( attempt++ ))
    sleep 2
  fi
done

if (( attempt > MAX_ATTEMPTS )); then
  print_error "Could not mount SMB share after $MAX_ATTEMPTS attempts"
  unset SMB_PASS
  exit 1
fi

# 4) Copy files as root into ~/.ssh
print_info "Copying SSH keys to $TARGET_FOLDER"
if sudo cp -R "$MOUNT_POINT"/* "$TARGET_FOLDER"/; then
  print_success "SSH keys copied"
else
  print_error "Failed to copy SSH keys"
fi

# 5) Unmount
print_info "Unmounting $MOUNT_POINT"
if sudo diskutil unmount "$MOUNT_POINT"; then
  print_success "Unmounted successfully"
else
  print_error "Failed to unmount $MOUNT_POINT"
fi

# 6) Clean up sensitive var
unset SMB_PASS
