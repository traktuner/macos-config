#!/usr/bin/env bash
set -euo pipefail
print_info "SSH Keyfiles"

SMB_SERVER="//172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET="$HOME/.ssh"
mkdir -p "$TARGET"

read -p "SMB‑User: " SMB_USER
read -s -p "SMB‑Pass: " SMB_PASS; echo

# mount_smbfs ist ab macOS dabei
printf "%s\n" "$SMB_PASS" | mount_smbfs "//$SMB_USER@$SMB_SERVER" "$MOUNT_POINT" \
  || { print_error "SMB mount failed"; exit 1; }

cp "$MOUNT_POINT"/* "$TARGET" && print_success "SSH keys copied"
umount "$MOUNT_POINT" && print_success "Unmounted" || print_error "Unmount failed"

unset SMB_PASS
