#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 0) Ensure HOME is set
# ─────────────────────────────────────────────────────────────────────────────
: "${HOME:?Environment variable HOME must be set}"

# Load shared print functions
source "$ROOT_DIR/core/functions.sh"
print_info "Mackup restore"

# ─────────────────────────────────────────────────────────────────────────────
# 1) Ensure Homebrew is available in this script's PATH
# ─────────────────────────────────────────────────────────────────────────────
if command -v brew &>/dev/null; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  print_error "brew not found; aborting Mackup restore"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2) Copy your Mackup config from iCloud to $HOME
# ─────────────────────────────────────────────────────────────────────────────
CLOUD_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
SOURCE_CFG="${CLOUD_DIR}/.config/mackup/.mackup.cfg"
TARGET_CFG="${HOME}/.mackup.cfg"

if [[ -f "${SOURCE_CFG}" ]]; then
  print_info "Copying Mackup config to ${TARGET_CFG}"
  if cp "${SOURCE_CFG}" "${TARGET_CFG}"; then
    print_success "Config copied"
  else
    print_error "Failed to copy config from ${SOURCE_CFG}"
    exit 1
  fi
else
  print_error "No Mackup config found at ${SOURCE_CFG}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3) Run 'mackup restore'
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
