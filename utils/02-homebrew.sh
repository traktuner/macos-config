#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Setting up Homebrew"
ask_for_sudo

# Install Casks in /Applications
export HOMEBREW_CASK_OPTS="--appdir=/Applications"
# Note: HOMEBREW_NO_QUARANTINE is deprecated since Homebrew 5.0.0

# 1) Install Homebrew
if ! command_exists brew; then
  HOMEBREW_LOG="/tmp/homebrew-install.log"
  print_info "Installing Homebrew... (log: $HOMEBREW_LOG)"

  if [[ "$(get_arch)" == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
  else
    HOMEBREW_PREFIX="/usr/local"
  fi

  retry 3 10 env NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    >"$HOMEBREW_LOG" 2>&1 \
    && print_success "Homebrew installed." \
    || { print_error "Homebrew installation failed. Check $HOMEBREW_LOG"; exit 1; }
else
  print_success "Homebrew is already installed."
fi

# 2) Init and persist shellenv
if [[ "$(get_arch)" == "arm64" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  BREW_SHELLENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
else
  eval "$(/usr/local/bin/brew shellenv)"
  BREW_SHELLENV='eval "$(/usr/local/bin/brew shellenv)"'
fi

# Persist for future zsh sessions (only in .zprofile, not .zshenv to avoid double-loading)
PROFILE="$HOME/.zprofile"
[[ -f "$PROFILE" ]] || touch "$PROFILE"
if ! grep -Fq 'brew shellenv' "$PROFILE"; then
  print_info "Adding Homebrew shellenv to $PROFILE"
  printf '\n# Load Homebrew\n%s\n' "$BREW_SHELLENV" >>"$PROFILE"
  print_success "Homebrew shellenv added to $PROFILE"
else
  print_success "Homebrew shellenv already in $PROFILE"
fi

# 3) Update Homebrew before installing
print_info "Updating Homebrew..."
brew update || print_error "brew update had issues"

# 4) Taps
print_info "Tapping repositories..."
for t in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --tap 2>/dev/null); do
  brew tap "$t" 2>/dev/null || print_error "Failed to tap $t"
done

# 5) Prompt whether to install Mac App Store (MAS) apps
print_info "Mac App Store (MAS) App Installation"
print_info "Note: MAS apps require being signed in to the App Store and may prompt for your password."
ask_for_confirmation "Install Mac App Store apps?"
if answer_is_yes; then
  INSTALL_MAS_APPS=true
else
  INSTALL_MAS_APPS=false
fi

# 6) Install from Brewfile (with up to 3 retries for transient download failures)
print_info "Installing from Brewfile..."

BREWFILE_TO_USE="$ROOT_DIR/core/Brewfile"
TMP_BREWFILE=""
if [[ "$INSTALL_MAS_APPS" == false ]]; then
  TMP_BREWFILE="$(mktemp)"
  grep -v '^mas ' "$ROOT_DIR/core/Brewfile" > "$TMP_BREWFILE"
  BREWFILE_TO_USE="$TMP_BREWFILE"
fi

BUNDLE_OK=false
for attempt in 1 2 3; do
  if brew bundle --file="$BREWFILE_TO_USE"; then
    BUNDLE_OK=true
    break
  fi
  if [[ $attempt -lt 3 ]]; then
    print_error "brew bundle attempt $attempt/3 had failures — retrying in 10s..."
    sleep 10
  fi
done
[[ -n "$TMP_BREWFILE" ]] && rm -f "$TMP_BREWFILE"

if $BUNDLE_OK; then
  print_success "All Brewfile items installed"
else
  print_error "Some Brewfile items failed after 3 attempts (check output above)"
fi

# 7) Upgrade and cleanup
print_info "Running brew maintenance..."
brew upgrade || true
brew cleanup --prune=30

# 8) Health check
if brew doctor 2>/dev/null; then
  print_success "brew doctor: OK"
else
  print_error "brew doctor reported issues (check output above)"
fi

# 9) Post-installation verification via brew bundle check
print_info "Verifying installations..."
if brew bundle check --file="$ROOT_DIR/core/Brewfile" 2>/dev/null; then
  print_success "All Brewfile items verified"
else
  print_error "Some Brewfile items are missing:"
  brew bundle check --file="$ROOT_DIR/core/Brewfile" --verbose 2>/dev/null || true
fi
