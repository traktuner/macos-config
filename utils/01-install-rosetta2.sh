#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"

print_info "Checking for Rosetta 2..."

# Check architecture - only Apple Silicon needs Rosetta
if [[ "$(uname -m)" != "arm64" ]]; then
  print_info "Intel Mac - Rosetta not needed."
  exit 0
fi

# Check if Rosetta is already installed via arch test
if arch -x86_64 /usr/bin/true 2>/dev/null; then
  print_success "Rosetta 2 already installed."
  exit 0
fi

print_info "Installing Rosetta 2..."
if sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license; then
  print_success "Rosetta 2 installed successfully."
else
  print_error "Rosetta 2 installation failed."
  exit 1
fi
