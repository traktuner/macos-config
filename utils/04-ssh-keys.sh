#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "SSH Keyfiles - mount SMB share and copy keys"

# Configuration
SMB_SERVER="172.16.10.200"
SMB_SHARE="tom"
SMB_SUBDIR="tresor/ssh"
MOUNT_POINT=""  # set dynamically after mount
TARGET_DIR="$HOME/.ssh"
TIMEOUT=30

# Cleanup function to ensure sensitive data and mounts are cleaned up
cleanup() {
  unset ENCODED_PASS ENCODED_USER SMB_PASS 2>/dev/null || true
  if [[ -n "${MOUNT_POINT:-}" ]] && mount | grep -q "on ${MOUNT_POINT} "; then
    diskutil unmount "${MOUNT_POINT}" &>/dev/null || \
      umount "${MOUNT_POINT}" &>/dev/null || true
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

# 3) Check if this share is already mounted somewhere
EXISTING_MOUNT=$(mount | grep "${SMB_SERVER}/${SMB_SHARE}" | awk '{print $3}' | head -1)
if [[ -n "$EXISTING_MOUNT" ]]; then
  print_info "Share already mounted at ${EXISTING_MOUNT}, unmounting..."
  diskutil unmount "$EXISTING_MOUNT" &>/dev/null || umount "$EXISTING_MOUNT" &>/dev/null || true
  sleep 1
fi

# 4) Mount SMB share via osascript (same code path as Finder — auto-creates mount point)
print_info "Mounting SMB share..."

# URL-encode credentials safely via stdin (never on command line / visible in ps)
ENCODED_PASS=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().rstrip('\n'), safe=''))" <<< "$SMB_PASS")
ENCODED_USER=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().rstrip('\n'), safe=''))" <<< "$SMB_USER")

# Mount via AppleScript — uses NetFS framework like Finder, auto-creates /Volumes/share
if ! osascript -e "mount volume \"smb://${ENCODED_USER}:${ENCODED_PASS}@${SMB_SERVER}/${SMB_SHARE}\"" &>/dev/null; then
  print_error "Failed to mount SMB share (check credentials and network)"
  unset ENCODED_PASS ENCODED_USER SMB_PASS
  exit 1
fi
unset ENCODED_PASS ENCODED_USER SMB_PASS

# Find the actual mount point (Finder may create /Volumes/tom or /Volumes/tom-1 etc.)
sleep 2
MOUNT_POINT=$(mount | grep "${SMB_SERVER}/${SMB_SHARE}" | awk '{print $3}' | head -1)

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  # Fallback: check common mount point names
  for candidate in "/Volumes/${SMB_SHARE}" "/Volumes/${SMB_SHARE}-1" "/Volumes/${SMB_SHARE}-2"; do
    if [[ -d "$candidate" ]]; then
      MOUNT_POINT="$candidate"
      break
    fi
  done
fi

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  print_error "SMB share mounted but mount point not found"
  exit 1
fi
print_success "SMB share mounted at ${MOUNT_POINT}"

# Wait for mount to become accessible
print_info "Waiting for share to become accessible..."
elapsed=0
while [[ ! -d "${MOUNT_POINT}/${SMB_SUBDIR}" && ${elapsed} -lt ${TIMEOUT} ]]; do
  sleep 1
  (( elapsed++ ))
done

# Source directory within the mounted share
SOURCE_DIR="${MOUNT_POINT}/${SMB_SUBDIR}"
if [[ ! -d "$SOURCE_DIR" ]]; then
  print_error "SSH key directory not found at ${SOURCE_DIR}"
  print_info "Contents of ${MOUNT_POINT}:"
  ls -la "${MOUNT_POINT}/" 2>/dev/null || true
  exit 1
fi

# 5) Copy SSH keys if any exist
if compgen -G "${SOURCE_DIR}/*" > /dev/null; then
  print_info "Copying SSH keys to ${TARGET_DIR}..."

  # Create backup of existing keys
  if [[ -d "${TARGET_DIR}" && "$(ls -A "${TARGET_DIR}" 2>/dev/null)" ]]; then
    BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Creating backup of existing keys in ${BACKUP_DIR}"
    cp -R "${TARGET_DIR}" "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
  fi

  # Copy new keys
  if cp -R "${SOURCE_DIR}"/* "${TARGET_DIR}/"; then
    print_success "SSH keys copied"

    # Set correct permissions on SSH files
    print_info "Setting permissions on SSH files..."
    # Private keys: 600 (all files without .pub extension, excluding known_hosts/config)
    find "${TARGET_DIR}" -maxdepth 1 -type f ! -name "*.pub" ! -name "known_hosts*" ! -name "config" ! -name "authorized_keys" -exec chmod 600 {} \;
    # Public keys: 644
    find "${TARGET_DIR}" -maxdepth 1 -type f -name "*.pub" -exec chmod 644 {} \;
    # Config and special files
    [[ -f "${TARGET_DIR}/config" ]] && chmod 600 "${TARGET_DIR}/config"
    [[ -f "${TARGET_DIR}/authorized_keys" ]] && chmod 600 "${TARGET_DIR}/authorized_keys"
    find "${TARGET_DIR}" -maxdepth 1 -type f -name "known_hosts*" -exec chmod 644 {} \;

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
  print_error "No files found under ${SOURCE_DIR}; skipping copy."
fi

# 6) Unmount the share
print_info "Unmounting ${MOUNT_POINT}..."
if diskutil unmount "${MOUNT_POINT}" 2>/dev/null; then
  print_success "Unmounted share"
elif umount "${MOUNT_POINT}" 2>/dev/null; then
  print_success "Unmounted share (umount)"
else
  print_error "Failed to unmount share (will be cleaned up on exit)"
fi

print_success "SSH keys setup completed"
