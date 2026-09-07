#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"

# Load configuration
CONFIG_FILE="$ROOT_DIR/utils/config.properties"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  print_info "Configuration loaded from config.properties"
else
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

print_info "SSH Keyfiles – mounting SMB share via Keychain and copying keys"

# Configuration (can be overridden by deploy.properties)
SMB_SERVER="${SMB_SERVER:-172.16.10.200}"
SMB_USER_PATH="${SMB_USER_PATH:-tom/tresor/ssh}"
MOUNT_POINT="${SMB_MOUNT_POINT:-/Volumes/ssh}"
SMB_TIMEOUT="${SMB_TIMEOUT:-30}"
TARGET_DIR="$HOME/.ssh"
SSH_PERMS=600

# Track state for cleanup
MOUNTED=false

# ─────────────────────────────────────────────────────────────────────────────
# 1) Get credentials from Keychain or prompt (shared helper in core/functions.sh)
# ─────────────────────────────────────────────────────────────────────────────
get_smb_credentials || exit 1

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup Trap - ensures resources are released on exit (shared helper)
# ─────────────────────────────────────────────────────────────────────────────
trap smb_cleanup EXIT INT TERM HUP

# ─────────────────────────────────────────────────────────────────────────────
# 2) Ensure target dir exists with proper permissions
# ─────────────────────────────────────────────────────────────────────────────
ensure_directory "${TARGET_DIR}" false
chmod 700 "${TARGET_DIR}"
print_success "SSH directory prepared with correct permissions"

# ─────────────────────────────────────────────────────────────────────────────
# 3) Unmount stale share if present, then mount (shared helpers)
# ─────────────────────────────────────────────────────────────────────────────
unmount_stale_share
mount_smb_share "${SMB_USER_PATH}"

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
# 7) Cleanup handled by trap
# ─────────────────────────────────────────────────────────────────────────────
print_success "SSH keys setup completed successfully"
