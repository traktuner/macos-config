#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles – mounting SMB share and copying keys"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
SMB_PATH="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="${HOME}/.ssh"   # ← always use braces, never a trailing '?'
TIMEOUT=30                  # seconds to wait for the volume

# ─────────────────────────────────────────────────────────────────────────────
# 1) Prompt for credentials
# ─────────────────────────────────────────────────────────────────────────────
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo

# ─────────────────────────────────────────────────────────────────────────────
# 2) Ensure target and mount-point exist
# ─────────────────────────────────────────────────────────────────────────────
ensure_directory "${TARGET_DIR}" false
ensure_directory "${MOUNT_POINT}" true

# ─────────────────────────────────────────────────────────────────────────────
# 3) Unmount stale share, if present
# ─────────────────────────────────────────────────────────────────────────────
if mount | grep -q "on ${MOUNT_POINT} "; then
  print_info "Unmounting stale share at ${MOUNT_POINT}…"
  sudo diskutil unmount "${MOUNT_POINT}" &>/dev/null \
    && print_success "Stale share unmounted" \
    || print_error "Failed to unmount stale share"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4) Trigger Finder mount (shows GUI prompt)
# ─────────────────────────────────────────────────────────────────────────────
print_info "Opening Finder to mount smb://…"
open "smb://${SMB_USER}:${SMB_PASS}@${SMB_PATH}" || true

# ─────────────────────────────────────────────────────────────────────────────
# 5) Wait up to ${TIMEOUT}s for the volume to appear
# ─────────────────────────────────────────────────────────────────────────────
print_info "Waiting up to ${TIMEOUT}s for ${MOUNT_POINT} to appear…"
elapsed=0
while [[ ! -d "${MOUNT_POINT}" && ${elapsed} -lt ${TIMEOUT} ]]; do
  sleep 1
  (( elapsed++ ))
done

if [[ ! -d "${MOUNT_POINT}" ]]; then
  print_error "Mount did not appear within ${TIMEOUT}s. Aborting."
  unset SMB_PASS
  exit 1
fi
print_success "SMB share mounted at ${MOUNT_POINT}"

# ─────────────────────────────────────────────────────────────────────────────
# 6) Copy SSH keys (with sudo to avoid permission issues)
# ─────────────────────────────────────────────────────────────────────────────
print_info "Copying SSH keys to ${TARGET_DIR}…"
if sudo cp -R "${MOUNT_POINT}"/* "${TARGET_DIR}/"; then
  print_success "SSH keys copied"
else
  print_error "Failed to copy SSH keys"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7) Unmount the share
# ─────────────────────────────────────────────────────────────────────────────
print_info "Unmounting ${MOUNT_POINT}…"
if sudo diskutil unmount "${MOUNT_POINT}"; then
  print_success "Unmounted share"
else
  print_error "Failed to unmount share"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8) Clean up sensitive data
# ─────────────────────────────────────────────────────────────────────────────
unset SMB_PASS
