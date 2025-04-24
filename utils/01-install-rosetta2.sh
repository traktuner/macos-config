#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"

print_info "Checking for Rosetta 2…"
if [[ "$(uname -p)" != "arm" ]]; then
  print_info "Intel Mac – Rosetta not needed."
  exit 0
fi

if pgrep -q oahd; then
  print_success "Rosetta 2 already installed."
  exit 0
fi

print_info "Installing Rosetta 2…"
sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license
if pgrep -q oahd; then
  print_success "Rosetta installation verified."
else
  print_error "Rosetta 2 daemon not found – installation failed."
  exit 1
fi
