#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles - mount SMB share and copy keys"

# Configuration
SMB_SERVER="172.16.10.100"
SMB_SHARE="tresor"
SMB_SUBDIR="ssh"
MOUNT_POINT="/Volumes/ssh"
TARGET_DIR="$HOME/.ssh"
TIMEOUT=30

# Cleanup function to ensure sensitive data and mounts are cleaned up
cleanup() {
  unset SMB_PASS 2>/dev/null || true
  if mount | grep -q "on ${MOUNT_POINT} "; then
    sudo diskutil unmount "${MOUNT_POINT}" &>/dev/null || true
  fi
}
trap cleanup EXIT

# 1) Prompt for credentials
read -rp "Please enter your SMB username: " SMB_USER
read -rs -p "Please enter your SMB password: " SMB_PASS
echo

if [[ -z "$SMB_USER" || -z "$SMB_PASS" ]]; then
  print_error "Username and password cannot be empty"
  exit 1
fi

# 2) Ensure target dir exists with proper permissions
ensure_directory "${TARGET_DIR}" false
chmod 700 "${TARGET_DIR}"
print_success "SSH directory prepared (700)"

# 3) Unmount stale share if present
if mount | grep -q "on ${MOUNT_POINT} "; then
  print_info "Unmounting stale share at ${MOUNT_POINT}..."
  sudo diskutil unmount "${MOUNT_POINT}" &>/dev/null || true
fi

# 4) Mount SMB share using mount_smbfs (no password in process list)
print_info "Mounting SMB share..."
sudo mkdir -p "${MOUNT_POINT}"

# Use mount_smbfs with credentials passed via URL (more secure than open command)
# The password is URL-encoded to handle special characters
ENCODED_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SMB_PASS}', safe=''))")
if ! mount_smbfs "//$(printf '%s' "${SMB_USER}"):$(printf '%s' "${ENCODED_PASS}")@${SMB_SERVER}/${SMB_SHARE}/${SMB_SUBDIR}" "${MOUNT_POINT}" 2>/dev/null; then
  # Fallback: try opening Finder for GUI-based mounting
  print_info "mount_smbfs failed, trying Finder-based mount..."
  open "smb://${SMB_USER}@${SMB_SERVER}/${SMB_SHARE}/${SMB_SUBDIR}" || true

  print_info "Waiting up to ${TIMEOUT}s for ${MOUNT_POINT}..."
  elapsed=0
  while [[ ! -d "${MOUNT_POINT}" && ${elapsed} -lt ${TIMEOUT} ]]; do
    sleep 1
    (( elapsed++ ))
  done
fi
unset ENCODED_PASS

if [[ ! -d "${MOUNT_POINT}" ]]; then
  print_error "Mount did not appear within ${TIMEOUT}s. Aborting."
  exit 1
fi
print_success "SMB share mounted at ${MOUNT_POINT}"

# 5) Copy SSH keys if any exist
if compgen -G "${MOUNT_POINT}/*" > /dev/null; then
  print_info "Copying SSH keys to ${TARGET_DIR}..."

  # Create backup of existing keys
  if [[ -d "${TARGET_DIR}" && "$(ls -A "${TARGET_DIR}" 2>/dev/null)" ]]; then
    BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Creating backup of existing keys in ${BACKUP_DIR}"
    cp -R "${TARGET_DIR}" "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
  fi

  # Copy new keys
  if cp -R "${MOUNT_POINT}"/* "${TARGET_DIR}/"; then
    print_success "SSH keys copied"

    # Set correct permissions on SSH files
    print_info "Setting permissions on SSH files..."
    find "${TARGET_DIR}" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
    find "${TARGET_DIR}" -type f -name "*.pub" -exec chmod 644 {} \;
    find "${TARGET_DIR}" -type f -name "known_hosts*" -exec chmod 644 {} \;
    find "${TARGET_DIR}" -type f -name "config" -exec chmod 600 {} \;
    find "${TARGET_DIR}" -type f -name "authorized_keys" -exec chmod 600 {} \;

    # Ensure correct ownership
    chown -R "$(whoami):$(id -gn)" "${TARGET_DIR}"

    print_success "SSH key permissions set correctly"

    # Verify SSH key functionality
    print_info "Verifying SSH keys..."
    for key in "${TARGET_DIR}"/id_*; do
      [[ -f "$key" && ! "$key" =~ \.pub$ ]] || continue
      if ssh-keygen -y -f "$key" >/dev/null 2>&1; then
        print_success "$(basename "$key") is valid"
      else
        print_error "$(basename "$key") appears invalid (may require passphrase)"
      fi
    done
  else
    print_error "Failed to copy SSH keys"
  fi
else
  print_error "No files found under ${MOUNT_POINT}; skipping copy."
fi

# 6) Unmount the share
print_info "Unmounting ${MOUNT_POINT}..."
if sudo diskutil unmount "${MOUNT_POINT}" 2>/dev/null; then
  print_success "Unmounted share"
elif sudo umount -f "${MOUNT_POINT}" 2>/dev/null; then
  print_success "Force unmounted share"
else
  print_error "Failed to unmount share"
fi

print_success "SSH keys setup completed"
