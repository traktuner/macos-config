#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Setting up Homebrew"
ask_for_sudo

# Install Casks in /Applications
export HOMEBREW_CASK_OPTS="--appdir=/Applications"

# 1) Install Homebrew
if ! command -v brew &>/dev/null; then
  HOMEBREW_LOG="/tmp/homebrew-install.log"
  print_info "Installing Homebrew… (log → $HOMEBREW_LOG)"
  
  # Determine Homebrew path based on architecture
  if [[ "$(get_arch)" == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
  else
    HOMEBREW_PREFIX="/usr/local"
  fi
  
  retry 3 10 env NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    >"$HOMEBREW_LOG" 2>&1 \
    && print_success "Homebrew installed." \
    || { print_error "Homebrew installation failed"; exit 1; }
else
  print_success "Homebrew is already installed."
fi

# 2) Init and persist shellenv
# a) in this script:
if [[ "$(get_arch)" == "arm64" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  BREW_SHELLENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
else
  eval "$(/usr/local/bin/brew shellenv)"
  BREW_SHELLENV='eval "$(/usr/local/bin/brew shellenv)"'
fi

# b) for all future zsh sessions:
for PROFILE in "$HOME/.zprofile" "$HOME/.zshenv"; do
  [[ -f $PROFILE ]] || touch "$PROFILE"
  if ! grep -Fxq "$BREW_SHELLENV" "$PROFILE"; then
    print_info "Appending Homebrew shellenv to $PROFILE"
    printf '\n# Load Homebrew\n%s\n' "$BREW_SHELLENV" >>"$PROFILE"
    print_success "Appended brew shellenv to $PROFILE"
  fi
done

# 3) Taps
print_info "Tapping repositories…"
for t in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --tap); do
  retry 3 5 brew tap "$t" || exit 1
done

# 4) Prefetch
print_info "Prefetching formulas and casks…"
for f in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --formula); do
  retry 3 5 brew fetch "$f" || exit 1
done
for c in $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --cask); do
  retry 3 5 brew fetch --cask "$c" || exit 1
done

# Prompt whether to install Mac App Store (MAS) apps
print_info "Mac App Store (MAS) App Installation"
while true; do
  read -rp "Do you want to install Mac App Store apps (mas)? [yes/no]: " yn
  yn_lower=$(echo "$yn" | tr '[:upper:]' '[:lower:]')
  case "$yn_lower" in
    y|j|ja|yes ) INSTALL_MAS_APPS=true; break ;;
    n|no|nein ) INSTALL_MAS_APPS=false; break ;;
    * ) echo "Invalid input. Please type 'yes' or 'no'." ;;
  esac
done

# 5) Install: always formulas and casks, MAS apps optional
print_info "Installing from Brewfile…"

if [ "$INSTALL_MAS_APPS" = false ]; then
  TMP_BREWFILE="$(mktemp)"
  grep -v '^mas ' "$ROOT_DIR/core/Brewfile" > "$TMP_BREWFILE"
  retry 3 5 brew bundle --file="$TMP_BREWFILE" || exit 1
  rm -f "$TMP_BREWFILE"
else
  retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1
fi

# 6) Brew maintenance
retry 2 5 brew update
retry 2 5 brew upgrade
retry 2 5 brew cleanup

# 7) Health check
if brew doctor; then
  print_success "brew doctor: OK"
else
  print_error "brew doctor reported issues"
fi

# 8) Post-installation verification
print_info "Verifying key installations..."
for app in "Visual Studio Code" "Firefox" "Warp"; do
  if [[ -d "/Applications/$app.app" ]]; then
    print_success "$app installed successfully"
  else
    print_error "$app not found in /Applications"
  fi
done
