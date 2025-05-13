#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "Mackup restore & configuration profile"

# ─────────────────────────────────────────────────────────────────────────────
# 1) Initialize Homebrew in this Bash script
# ─────────────────────────────────────────────────────────────────────────────
if [[ -x /opt/homebrew/bin/brew ]]; then
  # Apple Silicon
  eval "$(/opt/homebrew/bin/brew shellenv)"
  BREW_PREFIX="/opt/homebrew"
elif [[ -x /usr/local/bin/brew ]]; then
  # Intel
  eval "$(/usr/local/bin/brew shellenv)"
  BREW_PREFIX="/usr/local"
else
  print_error "brew not found; aborting"
  exit 1
fi

# ensure brew bin & sbin are in PATH
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
# 2) Confirm mackup is on PATH
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v mackup &>/dev/null; then
  print_error "mackup binary still not found even after shellenv—aborting"
  exit 1
else
  print_success "Found mackup at $(command -v mackup)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3) Copy Mackup config from iCloud Drive
# ─────────────────────────────────────────────────────────────────────────────
: "${HOME:?HOME must be set}"
CLOUD_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
SOURCE_CFG="${CLOUD_DIR}/.config/mackup/.mackup.cfg"
TARGET_CFG="${HOME}/.mackup.cfg"

print_info "Copying Mackup config to $TARGET_CFG"
if [[ -f "$SOURCE_CFG" ]]; then
  cp "$SOURCE_CFG" "$TARGET_CFG" && print_success "Config copied" \
    || { print_error "Failed to copy config"; exit 1; }
else
  print_error "No Mackup config at $SOURCE_CFG"; exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4) Run `mackup restore`
# ─────────────────────────────────────────────────────────────────────────────
print_info "Running 'mackup restore'…"
if mackup restore; then
  print_success "Mackup restore completed"
else
  print_error "Mackup restore failed"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5) Open configuration profile for interactive install
# ─────────────────────────────────────────────────────────────────────────────
PROFILE_PATH="${CLOUD_DIR}/FamilyConfig.mobileconfig"
if [[ -f "$PROFILE_PATH" ]]; then
  print_info "Opening configuration profile in System Settings…"
  open "$PROFILE_PATH"
  print_success "Please install the profile in the System Settings UI."
else
  print_error "No configuration profile at $PROFILE_PATH; skipping"
fi
