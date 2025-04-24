#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Mackup restore"

: "${HOME:?HOME not set}"

# ensure brew on PATH
if command -v brew &>/dev/null; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  print_error "brew not found"; exit 1
fi

CLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
SRC="$CLOUD/.config/mackup/.mackup.cfg"
DEST="$HOME/.mackup.cfg"

if [[ -f "$SRC" ]]; then
  print_info "Copying mackup config…"
  cp "$SRC" "$DEST" && print_success "Config copied" || { print_error "Copy failed"; exit 1; }
else
  print_error "No mackup config at $SRC"; exit 1
fi

if command -v mackup &>/dev/null; then
  print_info "Running mackup restore…"
  mackup restore && print_success "Mackup done" || { print_error "Mackup failed"; exit 1; }
else
  print_error "mackup not installed"; exit 1
fi
