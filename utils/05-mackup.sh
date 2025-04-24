#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"
print_info "Mackup restore"

# ─────────────────────────────────────────────────────────────────────────────
# Ensure Homebrew is on PATH in this script too
# ─────────────────────────────────────────────────────────────────────────────
if command -v brew &>/dev/null; then
  # this updates PATH/LDFLAGS/etc for macOS ARM+Intel installs
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  print_error "brew not found; skipping Mackup restore"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Copy Mackup config from iCloud
# ─────────────────────────────────────────────────────────────────────────────
CLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
SOURCE_CFG="$CLOUD_DIR/.config/mackup/.mackup.cfg"

if [[ -f "$SOURCE_CFG" ]]; then
  print_info "Copying Mackup config to $HOME…"
  cp "$SOURCE_CFG" "$HOME/.mackup.cfg" \
    && print_success "Config copied" \
    || { print_error "Failed to copy config"; exit 1; }
else
  print_error "No Mackup config found at $SOURCE_CFG"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Run the restore
# ─────────────────────────────────────────────────────────────────────────────
if command -v mackup &>/dev/null; then
  if mackup restore; then
    print_success "Mackup restore completed"
  else
    print_error "Mackup restore failed"
    exit 1
  fi
else
  print_error "mackup binary not found after brew setup"
  exit 1
fi
