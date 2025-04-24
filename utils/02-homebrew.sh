#!/usr/bin/env bash
set -euo pipefail

# FUNCTIONS aus core laden (wird im bootstrap bereits exportiert)
source "$ROOT_DIR/core/functions.sh"

print_info "Homebrew setup"

# retry-Funktion: retry <max-tries> <delay-secs> <command…>
retry() {
  local -r -i max_tries="${1:-3}"
  local -r -i delay_secs="${2:-5}"
  shift 2
  local -i attempt=1

  until "$@"; do
    if (( attempt >= max_tries )); then
      print_error "Command '$*' failed after $attempt tries."
      return 1
    else
      print_error "Attempt $attempt/$max_tries for '$*' failed. Retrying in $delay_secs s…"
      sleep "$delay_secs"
      (( attempt++ ))
    fi
  done

  print_success "Command '$*' succeeded on attempt $attempt."
}

# 1) Homebrew selbst installieren
if ! command -v brew &>/dev/null; then
  print_info "Installing Homebrew…"
  retry 3 10 env NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { print_error "Homebrew installation failed"; exit 1; }
  # Umgebung für brew
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  print_success "Homebrew is already installed."
fi

# 2) Brewfile einlesen
print_info "Running brew bundle…"
retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1

# 3) Cleanup, Upgrade & Update
print_info "Cleaning up…"
retry 2 5 brew cleanup

print_info "Upgrading…"
retry 2 5 brew upgrade

print_info "Updating…"
retry 2 5 brew update

# 4) Abschließender Check
if brew doctor; then
  print_success "brew doctor: All good!"
else
  print_error "brew doctor found issues."
fi
