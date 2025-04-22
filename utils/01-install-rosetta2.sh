#!/usr/bin/env bash
set -euo pipefail
print_info "Checking Rosetta 2…"

if [[ "$(uname -p)" == "arm" ]]; then
  if pgrep -q oahd; then
    print_success "Rosetta 2 already installed"
  else
    print_info "Installing Rosetta 2…"
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license \
      && print_success "Rosetta installed" \
      || { print_error "Rosetta install failed"; exit 1; }
  fi
else
  print_info "Intel Mac – no Rosetta needed"
fi
