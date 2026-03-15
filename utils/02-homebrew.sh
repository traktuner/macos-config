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

# 6) Install from Brewfile
print_info "Installing from Brewfile..."

if [[ "$INSTALL_MAS_APPS" == false ]]; then
  TMP_BREWFILE="$(mktemp)"
  grep -v '^mas ' "$ROOT_DIR/core/Brewfile" > "$TMP_BREWFILE"
  brew bundle --file="$TMP_BREWFILE" --no-lock || print_error "Some Brewfile items failed"
  rm -f "$TMP_BREWFILE"
else
  brew bundle --file="$ROOT_DIR/core/Brewfile" --no-lock || print_error "Some Brewfile items failed"
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

# 9) Post-installation verification
print_info "Verifying key installations..."
local_failed=0
for app in "Visual Studio Code" "Firefox" "Warp"; do
  if [[ -d "/Applications/$app.app" ]]; then
    print_success "$app installed"
  else
    print_error "$app not found in /Applications"
    ((local_failed++)) || true
  fi
done

if ((local_failed == 0)); then
  print_success "All key apps verified"
fi
