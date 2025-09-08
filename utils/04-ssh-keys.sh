#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles – mounting SMB share via Finder and copying keys"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
SMB_PATH="172.16.10.100/tresor/ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"
TIMEOUT=30
SSH_PERMS=600

# ─────────────────────────────────────────────────────────────────────────────
# 1) Prompt for credentials
# ─────────────────────────────────────────────────────────────────────────────
read -p "Please enter your SMB username: " SMB_USER
read -s -p "Please enter your SMB password: " SMB_PASS
echo

# Validate input
if [[ -z "$SMB_USER" || -z "$SMB_PASS" ]]; then
  print_error "Username and password cannot be empty"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2) Ensure target dir exists with proper permissions
# ─────────────────────────────────────────────────────────────────────────────
ensure_directory "${TARGET_DIR}" false
chmod 700 "${TARGET_DIR}"
print_success "SSH directory prepared with correct permissions"

# ─────────────────────────────────────────────────────────────────────────────
# 3) Unmount stale share if present
# ─────────────────────────────────────────────────────────────────────────────
if mount | grep -q "on ${MOUNT_POINT} "; then
  print_info "Unmounting stale share at ${MOUNT_POINT}…"
  sudo diskutil unmount "${MOUNT_POINT}" &>/dev/null \
    && print_success "Stale share unmounted" \
    || print_error "Failed to unmount stale share"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4) Trigger Finder mount (opens GUI prompt)
# ─────────────────────────────────────────────────────────────────────────────
print_info "Opening Finder to mount smb://…"
open "smb://${SMB_USER}:${SMB_PASS}@${SMB_PATH}" || true

# ─────────────────────────────────────────────────────────────────────────────
# 5) Wait up to $TIMEOUT seconds for the mount-point to appear
# ─────────────────────────────────────────────────────────────────────────────
print_info "Waiting up to ${TIMEOUT}s for ${MOUNT_POINT}…"
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
# 6) Copy SSH keys if any exist
# ─────────────────────────────────────────────────────────────────────────────
if compgen -G "${MOUNT_POINT}/*" > /dev/null; then
  print_info "Copying SSH keys to ${TARGET_DIR}…"
  
  # Create backup of existing keys
  if [[ -d "${TARGET_DIR}" && "$(ls -A "${TARGET_DIR}" 2>/dev/null)" ]]; then
    BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Creating backup of existing keys in ${BACKUP_DIR}"
    cp -R "${TARGET_DIR}" "${BACKUP_DIR}"
  fi
  
  # Copy new keys
  if sudo cp -R "${MOUNT_POINT}"/* "${TARGET_DIR}/"; then
    print_success "SSH keys copied"
    
    # Set correct permissions on SSH files
    print_info "Setting correct permissions on SSH files..."
    find "${TARGET_DIR}" -type f -name "id_*" -exec sudo chmod ${SSH_PERMS} {} \;
    find "${TARGET_DIR}" -type f -name "*.pub" -exec sudo chmod 644 {} \;
    find "${TARGET_DIR}" -type f -name "known_hosts" -exec sudo chmod 644 {} \;
    find "${TARGET_DIR}" -type f -name "config" -exec sudo chmod 600 {} \;
    
    # Change ownership back to the current user
    print_info "Changing ownership of SSH files to current user..."
    sudo chown -R "$(whoami):$(id -gn)" "${TARGET_DIR}"
    
    print_success "SSH key permissions set correctly"
    
    # Verify SSH key functionality
    if command_exists ssh-keygen; then
      print_info "Verifying SSH key functionality..."
      for key in "${TARGET_DIR}"/id_*; do
        if [[ -f "$key" && ! "$key" =~ \.pub$ ]]; then
          if ssh-keygen -y -f "$key" >/dev/null 2>&1; then
            print_success "SSH key $(basename "$key") is valid"
          else
            print_error "SSH key $(basename "$key") appears to be invalid"
          fi
        fi
      done
    fi
  else
    print_error "Failed to copy SSH keys"
  fi
else
  print_error "No files found under ${MOUNT_POINT}; skipping copy."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7) Unmount the share
# ─────────────────────────────────────────────────────────────────────────────
print_info "Unmounting ${MOUNT_POINT}…"
if sudo diskutil unmount "${MOUNT_POINT}"; then
  print_success "Unmounted share"
else
  print_error "diskutil unmount failed; trying umount -f…"
  if sudo umount -f "${MOUNT_POINT}"; then
    print_success "Force unmounted share"
  else
    print_error "Failed to unmount share"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8) Clean up sensitive data
# ─────────────────────────────────────────────────────────────────────────────
unset SMB_PASS
print_success "SSH keys setup completed successfully"
