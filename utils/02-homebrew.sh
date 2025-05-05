#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Homebrew setup"
ask_for_sudo

# install Casks in /Applications
export HOMEBREW_CASK_OPTS="--appdir=/Applications"

# 1) Install Homebrew
if ! command -v brew &>/dev/null; then
  HOMEBREW_LOG="/tmp/homebrew-install.log"
  print_info "Installing Homebrew… (log → $HOMEBREW_LOG)"
  retry 3 10 env NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    >"$HOMEBREW_LOG" 2>&1 \
    && print_success "Homebrew installed." \
    || { print_error "Homebrew install failed"; exit 1; }
else
  print_success "Homebrew is already installed."
fi

# 2) Init and persist shellenv
eval "$(/opt/homebrew/bin/brew shellenv)"
BREW_ENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
for P in "$HOME/.zprofile" "$HOME/.zshrc"; do
  [[ -f $P ]] || touch "$P"
  grep -Fxq "$BREW_ENV" "$P" || {
    print_info "Appending brew env to $P"
    printf '\n# Load Homebrew\n%s\n' "$BREW_ENV" >>"$P"
  }
done

# 3) Taps
print_info "Tapping GitHub repos…"
for t in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --tap); do
  retry 3 5 brew tap "$t" || exit 1
done

# 4) Prefetch
print_info "Prefetching formulae and casks…"
for f in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --formula); do
  retry 3 5 brew fetch "$f" || exit 1
done
for c in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --cask); do
  retry 3 5 brew fetch --cask "$c" || exit 1
done

# 5) Install
print_info "Running brew bundle…"
retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1

# 6) brew maintenance
retry 2 5 brew update
retry 2 5 brew upgrade
retry 2 5 brew cleanup

# 7) Health check
if brew doctor; then print_success "brew doctor: OK"; else print_error "brew doctor issues"; fi
