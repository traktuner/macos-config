#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Install Configuration Profile"

# ─────────────────────────────────────────────────────────────────────────────
# 1) Define paths
# ─────────────────────────────────────────────────────────────────────────────
# Ensure the HOME variable is set, which should always be the case.
: "${HOME:?HOME must be set}"

# Path to your iCloud Drive folder
CLOUD_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"

# Full path to the configuration profile
PROFILE_PATH="${CLOUD_DIR}/FamilyConfig.mobileconfig"

# ─────────────────────────────────────────────────────────────────────────────
# 2) Open configuration profile for interactive install
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "$PROFILE_PATH" ]]; then
  print_info "Opening configuration profile for installation…"
  
  # The 'open' command will launch System Settings and prompt for installation.
  if open "$PROFILE_PATH"; then
    print_success "Profile opened. Please follow the prompts in System Settings to complete the installation."
  else
    print_error "Failed to open the profile at: $PROFILE_PATH"
  fi
else
  print_error "Configuration profile not found at: $PROFILE_PATH"
  # We exit here because the script's main purpose could not be fulfilled.
  exit 1
fi