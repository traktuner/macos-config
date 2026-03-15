#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "macOS software updates"

# Show available updates first
print_info "Checking for available updates..."
sudo softwareupdate --list 2>&1 || true

ask_for_confirmation "Install all available macOS updates now?"
if answer_is_yes; then
  print_info "Running softwareupdate..."
  if sudo softwareupdate --install --all --agree-to-license; then
    print_success "Updates installed"
    print_info "A restart may be required for some updates to take effect."
  else
    print_error "Update failed or no updates available"
  fi
else
  print_info "Skipped macOS updates"
fi
