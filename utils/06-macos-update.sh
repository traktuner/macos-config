#!/usr/bin/env bash
set -euo pipefail
print_info "macOS updates"

ask_for_confirmation "Install all available updates now?"
if answer_is_yes; then
  /usr/sbin/softwareupdate --install --all \
    && print_success "Updates installed" \
    || print_error "Update failed"
else
  print_info "Skipped updates"
fi
