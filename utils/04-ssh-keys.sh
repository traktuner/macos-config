#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles – SMB mount with retry"

SMB="172.16.10.100/tresor/ssh"
MOUNT="/Volumes/ssh"
TARGET="$HOME/.ssh"

ensure_directory "$TARGET" false
ensure_directory "$MOUNT" true

MAX=3
attempt=1
while (( attempt <= MAX )); do
  print_info "Mount attempt $attempt/$MAX"
  read -p "SMB Username: " USER
  read -s -p "SMB Password: " PASS; echo

  retry 1 0 sudo mount_smbfs "//$USER:$PASS@$SMB" "$MOUNT" \
    && { print_success "Mounted SMB share"; break; } \
    || { print_error "Mount failed"; (( attempt++ )); sleep 5; }
done

if (( attempt > MAX )); then
  print_error "Cannot mount SMB after $MAX attempts"; exit 1
fi

print_info "Copying SSH keys…"
sudo cp "$MOUNT"/* "$TARGET"/ && print_success "Copied SSH keys" || print_error "Copy failed"

print_info "Unmounting share…"
sudo umount "$MOUNT" && print_success "Unmounted" || print_error "Unmount failed"
