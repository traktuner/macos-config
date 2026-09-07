#!/usr/bin/env bash
set -euo pipefail

# -- Logging
LOG_FILE="/tmp/macos-config.log"
log_message() {
  local level="$1" message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# -- User Prompts
answer_is_yes()    { [[ "$REPLY" =~ ^[Yy]$ ]]; }
ask_for_confirmation() {
  printf "\e[0;33m  %s (y/n) \e[0m" "$1"
  read -n1 -r; printf "\n"
}
ask_for_sudo() {
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# -- Print Helpers
print_info()    {
  printf "\n\e[0;34m  [info] %s\e[0m\n"  "$1"
  log_message "INFO" "$1"
}
print_success() {
  printf "\e[0;32m  [ok]   %s\e[0m\n"   "$1"
  log_message "SUCCESS" "$1"
}
print_error()   {
  printf "\e[0;31m  [err]  %s\e[0m\n"   "$1" >&2
  log_message "ERROR" "$1"
}

# -- System Information
get_system_info() {
  local version build
  version=$(sw_vers -productVersion)
  build=$(sw_vers -buildVersion)
  echo "macOS $version ($build) on $(uname -m)"
  echo "User: $(whoami)"
  echo "Home: $HOME"
  echo "Shell: $SHELL"
  echo "Date: $(date)"
}

get_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo arm64 || echo x64
}

# -- Retry a command up to N times
retry() {
  local -r -i max_tries="${1:-3}"
  local -r -i delay_secs="${2:-5}"
  shift 2
  local -i attempt=1
  until "$@"; do
    if (( attempt >= max_tries )); then
      print_error "Command '$*' failed after $attempt attempts."
      return 1
    fi
    print_error "Attempt $attempt/$max_tries for '$*' failed. Retrying in ${delay_secs}s..."
    sleep "$delay_secs"
    (( attempt++ ))
  done
  print_success "Command '$*' succeeded on attempt $attempt."
}

# -- defaults write wrapper (logs stderr, returns actual exit code)
safe_defaults_write() {
  local target="$1"; shift
  local stderr_output rc=0
  if [[ "$target" = /* ]]; then
    stderr_output=$(sudo defaults write "$target" "$@" 2>&1 >/dev/null) || rc=$?
  else
    stderr_output=$(defaults write "$target" "$@" 2>&1 >/dev/null) || rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    print_error "defaults write failed for: $target $* (rc=$rc: $stderr_output)"
  fi
  return $rc
}

# -- PlistBuddy wrapper
safe_plistbuddy() {
  if ! /usr/libexec/PlistBuddy -c "$1" "$2" 2>/dev/null; then
    print_error "PlistBuddy failed: $1 -> $2"
  fi
}

# -- killall wrapper
safe_killall() {
  if killall "$1" &>/dev/null; then
    print_success "Restarted $1"
  else
    print_info "$1 was not running"
  fi
}

# -- Ensure directory exists
ensure_directory() {
  local dir="$1" use_sudo="${2:-false}"
  if [[ ! -d "$dir" ]]; then
    if [[ "$use_sudo" == true ]]; then
      sudo mkdir -p "$dir"
    else
      mkdir -p "$dir"
    fi
    print_success "Created directory $dir"
  fi
}

# -- Download file + chmod
download_file() {
  local url="$1" dest="$2" mode="$3" use_sudo="${4:-false}"
  if [[ "$use_sudo" == true ]]; then
    sudo curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$dest"
    sudo chmod "$mode" "$dest"
  else
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$dest"
    chmod "$mode" "$dest"
  fi
  print_success "Downloaded $(basename "$dest")"
}

# -- Create a Time Machine local snapshot
tm_snapshot() {
  # tmutil localsnapshot has no --name flag; it auto-names with timestamp
  if tmutil localsnapshot 2>/dev/null; then
    print_success "Created Time Machine local snapshot"
  else
    print_error "Time Machine snapshot failed (TM may not be configured - continuing anyway)"
    return 1
  fi
}

# -- Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# -- Shared SMB share helpers (used by 04-ssh-keys.sh and 12-ai-config.sh)
#    The consumer sets SMB_SERVER / MOUNT_POINT and calls these in order.
#    Credentials land in the globals SMB_USER / SMB_PASS; the caller keeps the
#    same variable names as before so the cleanup trap keeps working.
# ─────────────────────────────────────────────────────────────────────────────

# Read SMB credentials from the Keychain (prompt + save on first use).
get_smb_credentials() {
  # Try to read from Keychain (stored with server as service name)
  if SMB_PASS=$(security find-internet-password -s "$SMB_SERVER" -w 2>/dev/null); then
    print_info "Credentials found in Keychain for $SMB_SERVER"
    # Extract the account/username from the "acct"<blob>="..." attribute line.
    # Splitting on the quote character is more robust than a sed regex chain.
    SMB_USER=$(security find-internet-password -s "$SMB_SERVER" 2>/dev/null \
      | awk -F'"' '/"acct"<blob>=/{print $(NF-1)}')
    if [[ -z "${SMB_USER:-}" ]]; then
      print_error "Found a Keychain password for $SMB_SERVER but could not read the username."
      return 1
    fi
    return 0
  fi

  # Fallback: prompt for credentials
  print_info "No credentials in Keychain for $SMB_SERVER. Please enter them once (will be saved)."
  read -r -p "Please enter your SMB username: " SMB_USER
  read -r -s -p "Please enter your SMB password: " SMB_PASS
  echo

  if [[ -z "${SMB_USER:-}" || -z "${SMB_PASS:-}" ]]; then
    print_error "Username and password cannot be empty"
    return 1
  fi

  # Save to Keychain so Finder can auto-authenticate next time
  print_info "Saving credentials to Keychain..."
  if security add-internet-password -s "$SMB_SERVER" -a "$SMB_USER" -w "$SMB_PASS" -r smb 2>/dev/null; then
    print_success "Credentials saved to Keychain (Finder will auto-authenticate)"
  else
    print_error "Failed to save credentials to Keychain"
  fi

  return 0
}

# Unmount a stale share if one is mounted at $MOUNT_POINT.
unmount_stale_share() {
  if mount | grep -q "on ${MOUNT_POINT} "; then
    print_info "Unmounting stale share at ${MOUNT_POINT}…"
    sudo diskutil unmount "${MOUNT_POINT}" &>/dev/null \
      && print_success "Stale share unmounted" \
      || print_error "Failed to unmount stale share"
  fi
}

# Mount SMB_SHARE_PATH (below SMB_SERVER) at MOUNT_POINT and wait up to
# SMB_TIMEOUT seconds (default 30). Requires Keychain credentials.
# Sets MOUNTED=true on success; exits the script on failure.
mount_smb_share() { # $1 = share path (e.g. tom/tresor/ssh)
  local share_path="$1"
  local smb_timeout="${SMB_TIMEOUT:-30}"
  print_info "Mounting SMB share (Finder will use Keychain credentials)…"
  open "smb://${SMB_SERVER}/${share_path}" || true

  print_info "Waiting up to ${smb_timeout}s for ${MOUNT_POINT}…"
  local elapsed=0
  while [[ ! -d "${MOUNT_POINT}" && ${elapsed} -lt ${smb_timeout} ]]; do
    sleep 1
    (( elapsed++ ))
  done

  if [[ ! -d "${MOUNT_POINT}" ]]; then
    print_error "Mount did not appear within ${smb_timeout}s. Aborting."
    print_info "Check that:"
    print_info "  • the server ${SMB_SERVER} is reachable (e.g. 'ping ${SMB_SERVER}')"
    print_info "  • the share path '${share_path}' is correct in config.properties"
    print_info "  • the Keychain credentials for ${SMB_SERVER} are valid"
    exit 1
  fi
  MOUNTED=true
  print_success "SMB share mounted at ${MOUNT_POINT}"
}

# Unmount MOUNT_POINT if MOUNTED=true and clear credential variables.
smb_cleanup() {
  local exit_code=$?
  print_info "Running cleanup..."
  if [[ "${MOUNTED:-false}" == "true" ]]; then
    print_info "Unmounting ${MOUNT_POINT}…"
    sudo diskutil unmount "${MOUNT_POINT}" &>/dev/null || \
      sudo umount -f "${MOUNT_POINT}" &>/dev/null || true
  fi
  unset SMB_PASS 2>/dev/null || true
  unset SMB_USER 2>/dev/null || true
  [[ $exit_code -eq 0 ]] && print_success "Cleanup completed successfully" || print_error "Cleanup completed with exit code: $exit_code"
  exit $exit_code
}

# -- Check macOS version (returns 0 if current >= required)
check_macos_version() {
  local required_version="$1"
  local current_version
  current_version=$(sw_vers -productVersion)
  if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" == "$required_version" ]]; then
    return 0
  else
    print_error "macOS $required_version or higher required. Current: $current_version"
    return 1
  fi
}

# -- Verify Full Disk Access by reading Safari bookmarks (reliable test on all macOS versions)
check_full_disk_access() {
  local safari_bookmarks="$HOME/Library/Safari/Bookmarks.plist"
  if cat "$safari_bookmarks" &>/dev/null; then
    return 0
  fi
  return 1
}

# -- Request Full Disk Access for Terminal (loop with max retries)
request_full_disk_access() {
  # Check if we already have FDA
  if check_full_disk_access; then
    print_success "Full Disk Access already granted"
    return 0
  fi

  print_info "Full Disk Access is required for Terminal..."
  print_info "Opening System Settings > Privacy & Security > Full Disk Access..."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

  local max_attempts=3
  local attempt=1

  while ((attempt <= max_attempts)); do
    print_info "Please enable your terminal app in Full Disk Access, then press any key."
    print_info "(Attempt $attempt of $max_attempts)"
    read -n1 -r -s; printf "\n"

    print_info "Verifying Full Disk Access..."
    if check_full_disk_access; then
      print_success "Full Disk Access verified!"
      return 0
    fi

    print_error "Full Disk Access not detected."
    if ((attempt < max_attempts)); then
      print_info "Make sure you toggled the switch for your terminal app and try again."
    fi
    ((attempt++))
  done

  print_error "Full Disk Access could not be verified after $max_attempts attempts. Aborting."
  return 1
}
