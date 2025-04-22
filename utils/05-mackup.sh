#!/usr/bin/env bash
set -euo pipefail
print_info "Mackup restore"

CONF="$HOME/Library/Mobile Documents/com~apple~CloudDocs/.config/mackup/.mackup.cfg"
if [[ -f "$CONF" ]]; then
  cp "$CONF" "$HOME" && print_success "Config copied"
  mackup restore && print_success "Mackup done" || print_error "Mackup failed"
else
  print_error "No config at $CONF"
fi
