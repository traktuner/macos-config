#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Configuring Dock layout"

# Resolve dockutil binary (may not be in PATH if Homebrew was just installed in this session)
DOCKUTIL=""
if command_exists dockutil; then
  DOCKUTIL="dockutil"
elif [[ -x "/opt/homebrew/bin/dockutil" ]]; then
  DOCKUTIL="/opt/homebrew/bin/dockutil"
elif [[ -x "/usr/local/bin/dockutil" ]]; then
  DOCKUTIL="/usr/local/bin/dockutil"
fi

if [[ -z "$DOCKUTIL" ]]; then
  print_error "dockutil not found. Install it first (brew install dockutil)."
  exit 1
fi

###############################################################################
# Define Dock layout
# Order matters — apps will appear in this exact sequence.
# System apps are in /System/Applications, third-party in /Applications.
###############################################################################
DOCK_APPS=(
  "/Applications/Safari.app"
  "/Applications/Firefox.app"
  "/Applications/Proton Mail.app"
  "/System/Applications/Messages.app"
  "/Applications/Beeper Desktop.app"
  "/Applications/Standard Notes.app"
  "/System/Applications/Photos.app"
  "/System/Applications/Music.app"
  "/Applications/VLC.app"
  "/System/Applications/Calendar.app"
  "/System/Applications/System Settings.app"
  "/Applications/Steam.app"
  "/Applications/CrossOver.app"
  "/Applications/Microsoft Teams.app"
  "/Applications/Visual Studio Code.app"
  "/System/Applications/App Store.app"
)

###############################################################################
# 1) Remove all existing Dock items
###############################################################################
print_info "Removing all current Dock items..."
"$DOCKUTIL" --remove all --no-restart

###############################################################################
# 2) Add apps in order
###############################################################################
print_info "Adding apps to Dock..."
added=0
for app in "${DOCK_APPS[@]}"; do
  app_name="$(basename "$app" .app)"
  if [[ -d "$app" ]]; then
    "$DOCKUTIL" --add "$app" --no-restart
    print_success "  Added: $app_name"
    ((added++))
  else
    print_error "  Not found: $app_name ($app) — skipping"
  fi
done
print_info "$added apps added to Dock"

###############################################################################
# 3) Add persistent-others: Applications folder + Downloads folder (stacks)
###############################################################################
print_info "Adding folder stacks..."

# Applications folder as stack (grid view, sorted by name)
"$DOCKUTIL" --add /Applications --view grid --display folder --sort name --section others --no-restart
print_success "  Added: Applications (stack)"

# Downloads folder as stack (fan view, sorted by date modified)
"$DOCKUTIL" --add "$HOME/Downloads" --view fan --display stack --sort datemodified --section others --no-restart
print_success "  Added: Downloads (stack, sorted by modification date)"

###############################################################################
# 4) Restart Dock to apply all changes
###############################################################################
print_info "Restarting Dock..."
killall Dock

print_success "Dock layout configured"
