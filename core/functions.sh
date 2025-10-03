#!/usr/bin/env bash
set -euo pipefail

# — Logging
LOG_FILE="/tmp/macos-config.log"
log_message() {
  local level="$1" message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# — User Prompts
answer_is_yes()    { [[ "$REPLY" =~ ^[Yy]$ ]]; }
ask_for_confirmation() {
  printf "\e[0;33m 🤔  %s (y/n) \e[0m" "$1"
  read -n1 -r; printf "\n"
}
ask_for_sudo() {
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# — Print Helpers
print_info()    { 
  printf "\n\e[0;34m 👊  %s\e[0m\n"  "$1"
  log_message "INFO" "$1"
}
print_success() { 
  printf "\e[0;32m 👍  %s\e[0m\n"   "$1"
  log_message "SUCCESS" "$1"
}
print_error()   { 
  printf "\e[0;31m 😡  %s\e[0m\n"   "$1"
  log_message "ERROR" "$1"
}

# — System Information
get_system_info() {
  echo "macOS $(sw_vers -productVersion) ($(uname -m))"
  echo "User: $(whoami)"
  echo "Home: $HOME"
}

# — Symlink with Confirmation
symlink_from_to() {
  local FROM="$1" TO="$2"
  if [[ ! -e "$TO" ]]; then
    ln -fs "$FROM" "$TO" && print_success "Symlinked $(basename "$TO")"
  elif [[ "$(readlink "$TO")" == "$FROM" ]]; then
    print_success "$(basename "$TO") already linked"
  else
    ask_for_confirmation "$(basename "$TO") exists. Overwrite?"
    if answer_is_yes; then
      rm -rf "$TO"
      ln -fs "$FROM" "$TO"
      print_success "Re-symlinked"
    else
      print_info "Skipped $(basename "$FROM")"
    fi
  fi
}

# — Text Manipulation
modify_file() {
  [[ ! -f "$3" ]] && print_error "File not found:" "$3" && return 1
  grep -qF "$2" "$3" || awk "/$1/{print;print \"$2\";next}1" "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}
modify_line() {
  awk "{gsub(\"$1\",\"$2\")}1" "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}
insert_to_file_after_line_number() {
  awk -v ins="$1" '1; NR=='"$2"'{print ins}' "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}
uncomment_line() {
  sed -i '' "/$1/s/^#//" "$2"
}
prepend_string_to_file() {
  printf "%s\n" "$1" | cat - "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}
line_exists() { grep -qFx "$1" "$2"; }
add_config() {
  local file="$1"
  local path="$2"
  local content="$3"
  local cfg="$path/$file"
  mkdir -p "$path"
  if [[ -f "$cfg" ]]; then
    while IFS= read -r line; do
      if line_exists "$line" "$cfg"; then
        print_info "Already in $file: $line"
        return
      fi
    done <<< "$content"
    printf "%s\n" "$content" >> "$cfg"
    print_success "Appended to $file"
  else
    printf "%s\n" "$content" > "$cfg"
    print_success "Created $file"
  fi
}

get_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo arm64 || echo x64
}

# — Retry a command up to N times
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
    print_error "Attempt $attempt/$max_tries for '$*' failed. Retrying in $delay_secs seconds..."
    sleep "$delay_secs"
    (( attempt++ ))
  done
  print_success "Command '$*' succeeded on attempt $attempt."
}

# — defaults write wrapper (catches errors, never exits)
safe_defaults_write() {
  local target="$1"; shift
  if [[ "$target" = /* ]]; then
    if sudo defaults write "$target" "$@"; then
      return 0
    fi
  else
    if defaults write "$target" "$@"; then
      return 0
    fi
  fi
  print_error "defaults write failed for: $target $*"
  return 0
}

# — PlistBuddy wrapper
safe_plistbuddy() {
  if ! /usr/libexec/PlistBuddy -c "$1" "$2"; then
    print_error "PlistBuddy failed: $1 → $2"
  fi
}

# — killall wrapper
safe_killall() {
  if killall "$1" &>/dev/null; then
    print_success "Restarted $1"
  else
    print_info "$1 was not running"
  fi
}

# — Ensure directory exists
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

# — Download file + chmod
download_file() {
  local url="$1" dest="$2" mode="$3" use_sudo="${4:-false}"
  if [[ "$use_sudo" == true ]]; then
    sudo curl -fsSL "$url" -o "$dest"
    sudo chmod "$mode" "$dest"
  else
    curl -fsSL "$url" -o "$dest"
    chmod "$mode" "$dest"
  fi
  print_success "Downloaded $url → $dest"
}

# — Load a LaunchDaemon into the system domain (root)
bootstrap_launch_daemon() {
  local plist="$1"
  local SUDO=""
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    SUDO="sudo"
  fi
  if [[ ! -f "$plist" ]]; then
    print_error "Plist not found: $plist"
    return 1
  fi
  $SUDO chown root:wheel "$plist" 2>/dev/null || true
  $SUDO chmod 644 "$plist" 2>/dev/null || true
  if ! $SUDO plutil -lint "$plist" >/dev/null 2>&1; then
    print_error "Invalid plist: $plist"
    $SUDO plutil -lint "$plist" || true
    return 1
  fi
  $SUDO launchctl bootout system "$plist" &>/dev/null || true
  if $SUDO launchctl bootstrap system "$plist"; then
    local label
    label="$(
      /usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null \
      || basename "$plist" .plist
    )"
    $SUDO launchctl enable "system/${label}" &>/dev/null || true
    $SUDO launchctl kickstart -k "system/${label}" &>/dev/null || true
    print_success "Bootstrapped $plist"
  else
    print_error "Failed to bootstrap $plist"
    return 1
  fi
}

# — Create a Time Machine local snapshot
tm_snapshot() {
  local name="$1" out="$2"
  if sudo tmutil localsnapshot --name "$name"; then
    print_success "Created TM snapshot: $name"
    echo "$name" > "$out"
  else
    print_error "tmutil snapshot failed"
    return 1
  fi
}

# — Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# — Check macOS version
check_macos_version() {
  local required_version="$1"
  local current_version=$(sw_vers -productVersion)
  if [[ "$(echo -e "$required_version\n$current_version" | sort -V | head -n1)" == "$required_version" ]]; then
    return 0
  else
    print_error "macOS $required_version or higher required. Current: $current_version"
    return 1
  fi
}

# — Request Full Disk Access for Terminal
request_full_disk_access() {
  print_info "Full Disk Access is required for Terminal..."
  print_info "Opening System Preferences to Privacy & Security..."
  
  # Open System Preferences directly to Privacy & Security
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
  
  print_info "Please enable Terminal in the Full Disk Access list, then return here."
  echo
  ask_for_confirmation "Have you enabled Full Disk Access for Terminal?"
  
  if answer_is_yes; then
    # Test Full Disk Access using the standard method most apps use
    local fda_enabled=false
    
    # Primary method: Try to access Mail Envelope Index (standard FDA test)
    if [[ -r "$HOME/Library/Mail/V10/MailData/Envelope Index" ]]; then
      fda_enabled=true
    fi
    
    # Fallback method: Try to access TCC database
    if [[ "$fda_enabled" == "false" && -r "$HOME/Library/Application Support/com.apple.TCC/TCC.db" ]]; then
      fda_enabled=true
    fi
    
    # Additional fallback: Try a simple defaults write that requires FDA
    if [[ "$fda_enabled" == "false" ]]; then
      print_info "Testing Full Disk Access with a defaults write command..."
      if defaults write com.apple.finder TestFDA -bool true 2>/dev/null; then
        defaults delete com.apple.finder TestFDA 2>/dev/null
        fda_enabled=true
      fi
    fi
    
    if [[ "$fda_enabled" == "true" ]]; then
      print_success "Full Disk Access is enabled!"
      return 0
    else
      print_error "Full Disk Access does not seem to be enabled yet."
      print_info "Please check the settings and try again."
      return 1
    fi
  else
    print_error "Full Disk Access is required to continue."
    return 1
  fi
}
