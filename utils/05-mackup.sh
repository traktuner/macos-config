#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "Mackup restore"

# ─────────────────────────────────────────────────────────────────────────────
# 1) Ensure Homebrew is on PATH (cover both ARM and Intel installs)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  print_error "brew not found; aborting Mackup restore"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2) Copy Mackup config from iCloud Drive
# ─────────────────────────────────────────────────────────────────────────────
: "${HOME:?HOME must be set}"

CLOUD_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
SOURCE_CFG="${CLOUD_DIR}/.config/mackup/.mackup.cfg"
TARGET_CFG="${HOME}/.mackup.cfg"

if [[ -f "$SOURCE_CFG" ]]; then
  print_info "Copying Mackup config to $TARGET_CFG"
  if cp "$SOURCE_CFG" "$TARGET_CFG"; then
    print_success "Config copied"
  else
    print_error "Failed to copy config"
    exit 1
  fi
else
  print_error "No Mackup config found at $SOURCE_CFG"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3) Run `mackup restore`
# ─────────────────────────────────────────────────────────────────────────────
if command -v mackup &>/dev/null; then
  print_info "Running 'mackup restore'…"
  if mackup restore; then
    print_success "Mackup restore completed"
  else
    print_error "Mackup restore failed"
    exit 1
  fi
else
  print_error "mackup binary not found; ensure you have 'brew install mackup'"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4) Install configuration profile from iCloud
# ─────────────────────────────────────────────────────────────────────────────
PROFILE_PATH="${CLOUD_DIR}/FamilyConfig.mobileconfig"
if [[ -f "$PROFILE_PATH" ]]; then
  print_info "Opening configuration profile in System Settings…"
  open "$PROFILE_PATH"
  print_success "Profile opened; please review and Install in the System Settings UI."
else
  print_error "No configuration profile found at $PROFILE_PATH; skipping"
fi