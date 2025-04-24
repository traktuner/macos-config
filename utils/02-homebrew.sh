#!/usr/bin/env bash
set -euo pipefail

# Load shared functions from core
source "$ROOT_DIR/core/functions.sh"

print_info "Homebrew setup"

# retry function: retry <max-tries> <delay-seconds> <command...>
retry() {
  local -r -i max_tries="${1:-3}"
  local -r -i delay_secs="${2:-5}"
  shift 2
  local -i attempt=1

  until "$@"; do
    if (( attempt >= max_tries )); then
      print_error "Command '$*' failed after $attempt attempts."
      return 1
    else
      print_error "Attempt $attempt/$max_tries for '$*' failed. Retrying in $delay_secs seconds..."
      sleep "$delay_secs"
      (( attempt++ ))
    fi
  done

  print_success "Command '$*' succeeded on attempt $attempt."
}

# -------------------------------------------------------------------
# 1) Install Homebrew itself if not already present
#    Logs output to a temporary file to keep the console clean
# -------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
  HOMEBREW_LOG="/tmp/homebrew-install.log"
  print_info "Installing Homebrew… (logging to $HOMEBREW_LOG)"
  
  if retry 3 10 env NONINTERACTIVE=1 /bin/bash -c \
       "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
       >"$HOMEBREW_LOG" 2>&1; then
    print_success "Homebrew installed successfully."
    # Initialize brew in current shell
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    print_error "Homebrew installation failed. See $HOMEBREW_LOG for details."
    exit 1
  fi
else
  print_success "Homebrew is already installed."
fi

# -------------------------------------------------------------------
# 2) Run brew bundle to install all items in Brewfile
# -------------------------------------------------------------------
print_info "Running brew bundle…"
retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1

# -------------------------------------------------------------------
# 3) Clean up, upgrade, and update installed formulae & casks
# -------------------------------------------------------------------
print_info "Cleaning up old downloads and cache…"
retry 2 5 brew cleanup

print_info "Upgrading installed formulae and casks…"
retry 2 5 brew upgrade

print_info "Updating Homebrew itself…"
retry 2 5 brew update

# -------------------------------------------------------------------
# 4) Final health check with brew doctor
# -------------------------------------------------------------------
if brew doctor; then
  print_success "brew doctor: All good!"
else
  print_error "brew doctor found issues."
fi
