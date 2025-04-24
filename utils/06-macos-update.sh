#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "macOS software updates"

ask_for_confirmation "Install all available macOS updates now?"
if answer_is_yes; then
  print_info "Running softwareupdate…"
  if sudo softwareupdate --install --all; then
    print_success "Updates installed"
  else
    print_error "Update failed"
    exit 1
  fi
else
  print_info "Skipped macOS updates"
fi
