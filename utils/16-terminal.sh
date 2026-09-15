#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Configuring Terminal.app"

TERMINAL_DOMAIN="com.apple.Terminal"
TERMINAL_PROFILE_NAME="Clear Dark"
PROFILE_FILE="$ROOT_DIR/assets/terminal/Clear Dark.terminal"

###############################################################################
# 1) Import the versioned profile (.terminal file) into Terminal.app
#    `open` registers the profile without opening a window.
###############################################################################

if [[ -f "$PROFILE_FILE" ]]; then
  print_info "Importing Terminal profile '$TERMINAL_PROFILE_NAME'..."
  if open "$PROFILE_FILE"; then
    print_success "Profile '$TERMINAL_PROFILE_NAME' imported"
  else
    print_error "Failed to import profile from '$PROFILE_FILE'"
  fi
else
  print_error "Profile file not found: $PROFILE_FILE — skipping import"
fi

###############################################################################
# 2) Make startup and default profile consistent
###############################################################################

print_info "Setting startup and default profile to '$TERMINAL_PROFILE_NAME'..."
safe_defaults_write "$TERMINAL_DOMAIN" "Startup Window Settings" -string "$TERMINAL_PROFILE_NAME"
safe_defaults_write "$TERMINAL_DOMAIN" "Default Window Settings" -string "$TERMINAL_PROFILE_NAME"
print_success "Startup and default profile set to '$TERMINAL_PROFILE_NAME'"

###############################################################################
# 3) Apply preferences to Terminal (takes effect on next launch)
#    Skip the restart when this script itself runs inside Terminal.app,
#    otherwise it would kill the user's own session.
###############################################################################

if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
  print_info "Running inside Terminal.app — skipping restart. Please relaunch Terminal manually."
else
  safe_killall Terminal
fi

print_success "Terminal.app configuration complete"
print_info "Changes take full effect after relaunching Terminal."
