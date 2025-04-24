#!/usr/bin/env bash
set -euo pipefail

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
print_info()    { printf "\n\e[0;34m 👊  %s\e[0m\n" "$1"; }
print_success() { printf "\e[0;32m 👍  %s\e[0m\n" "$1"; }
print_error()   { printf "\e[0;31m 😡  %s\e[0m\n" "$1"; }

# — Symlink with Confirmation
symlink_from_to() {
  local FROM="$1" TO="$2"
  if [[ ! -e "$TO" ]]; then
    ln -fs "$FROM" "$TO" && print_success "Symlinked $(basename "$TO")"
  elif [[ "$(readlink "$TO")" == "$FROM" ]]; then
    print_success "$(basename "$TO") already linked"
  else
    ask_for_confirmation "$(basename "$TO") exists. Overwrite?"
    if answer_is_yes; then rm -rf "$TO"; ln -fs "$FROM" "$TO"; print_success "Re-symlinked"; 
    else print_info "Skipped $(basename "$FROM")"; fi
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
  local file="$1" path="$2" content="$3" cfg="$path/$file"
  mkdir -p "$path"
  if [[ -f "$cfg" ]]; then
    while IFS= read -r line; do
      if line_exists "$line" "$cfg"; then print_info "Already in $file: $line"; return; fi
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

# — defaults write wrapper (auto-sudo on /Library)
safe_defaults_write() {
  local target="$1"; shift
  if [[ "$target" = /* ]]; then
    sudo defaults write "$target" "$@"
  else
    defaults write "$target" "$@"
  fi
  [[ $? -ne 0 ]] && print_error "defaults write failed for: $target $*"
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

# — Load a LaunchAgent into user session
bootstrap_launch_agent() {
  local plist="$1"
  launchctl bootout gui/"$UID" "$plist" &>/dev/null || true
  if launchctl bootstrap gui/"$UID" "$plist"; then
    print_success "Bootstrapped $plist"
  else
    print_error "Failed to bootstrap $plist"
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
