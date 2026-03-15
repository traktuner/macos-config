#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Install Configuration Profile"

: "${HOME:?HOME must be set}"

CLOUD_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
PROFILE_PATH="${CLOUD_DIR}/FamilyConfig.mobileconfig"

# Check if iCloud Drive is synced (may not be ready on fresh install)
if [[ ! -d "$CLOUD_DIR" ]]; then
  print_error "iCloud Drive not found at $CLOUD_DIR"
  print_info "Please sign in to iCloud and wait for sync, then run this script again."
  exit 1
fi

if [[ -f "$PROFILE_PATH" ]]; then
  print_info "Opening configuration profile for installation..."
  if open "$PROFILE_PATH"; then
    print_success "Profile opened. Follow the prompts in System Settings > General > Profiles to install."
    print_info "After installing, you may need to restart for all profile settings to take effect."
  else
    print_error "Failed to open the profile at: $PROFILE_PATH"
  fi
else
  print_error "Configuration profile not found at: $PROFILE_PATH"
  print_info "It may still be syncing from iCloud. Try again later."
  exit 1
fi
