#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "macOS system configuration"

###############################################################################
# Analytics & Privacy
###############################################################################
print_info "Configuring analytics & privacy..."
safe_defaults_write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false
safe_defaults_write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" ThirdPartyDataSubmit -bool false

###############################################################################
# General UI/UX
###############################################################################
print_info "Configuring UI/UX..."

# Mute startup sound
sudo nvram StartupMute=%01

# Save to disk (not iCloud) by default
safe_defaults_write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

# Expand save panel by default
safe_defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
safe_defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand print panel by default
safe_defaults_write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
safe_defaults_write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Quit printer app when jobs complete
safe_defaults_write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

# Show scrollbars only when scrolling
safe_defaults_write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"

# Disable auto-correct and related annoyances
safe_defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable auto text completion
safe_defaults_write NSGlobalDomain NSAutomaticTextCompletionEnabled -bool false

# Time Machine: don't prompt for new disks
safe_defaults_write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# Disable eject notification
safe_defaults_write com.apple.DiskArbitration.diskarbitrationd DADisableEjectNotification -bool true

# Disable guest user
safe_defaults_write "/Library/Preferences/com.apple.loginwindow" GuestEnabled -bool false

# Show all filename extensions
safe_defaults_write NSGlobalDomain AppleShowAllExtensions -bool true

# Disable the "Are you sure you want to open this application?" dialog
safe_defaults_write com.apple.LaunchServices LSQuarantine -bool false

###############################################################################
# Input
###############################################################################
print_info "Configuring input..."

# Disable press-and-hold for accent characters (enable key repeat instead)
safe_defaults_write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Set fast key repeat rate
safe_defaults_write NSGlobalDomain KeyRepeat -int 2
safe_defaults_write NSGlobalDomain InitialKeyRepeat -int 15

# Enable tap to click for trackpad
safe_defaults_write com.apple.AppleMultitouchTrackpad Clicking -bool true
safe_defaults_write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 2>/dev/null || true

###############################################################################
# Screen
###############################################################################
print_info "Configuring screen & screenshots..."

# Screenshots: save to Desktop, PNG format, no shadow
safe_defaults_write com.apple.screencapture location -string "${HOME}/Desktop"
safe_defaults_write com.apple.screencapture type -string "png"
safe_defaults_write com.apple.screencapture disable-shadow -bool true
# Disable HDR capture (Tahoe may default to HEIC in HDR mode)
safe_defaults_write com.apple.screencapture captureHDR -bool false

# Note: com.apple.screensaver askForPassword is deprecated since macOS High Sierra.
# Use a configuration profile (MDM) or System Settings > Lock Screen instead.

###############################################################################
# Finder
###############################################################################
print_info "Configuring Finder..."

# New Finder windows show Desktop
safe_defaults_write com.apple.finder NewWindowTarget -string "PfDe"
safe_defaults_write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Desktop/"

# Hide icons on desktop
safe_defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
safe_defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false
safe_defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false
safe_defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false

# Auto-open new Finder window when a volume is mounted
safe_defaults_write com.apple.frameworks.diskimages auto-open-ro-root -bool true
safe_defaults_write com.apple.frameworks.diskimages auto-open-rw-root -bool true
safe_defaults_write com.apple.finder OpenWindowForNewRemovableDisk -bool true

# Spring-load directories
safe_defaults_write NSGlobalDomain com.apple.springing.enabled -bool true
safe_defaults_write NSGlobalDomain com.apple.springing.delay -float 0

# Sort folders first
safe_defaults_write com.apple.finder _FXSortFoldersFirst -bool true
safe_defaults_write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true

# Search current folder by default
safe_defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable extension change warning
safe_defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Avoid .DS_Store on network and USB volumes
safe_defaults_write com.apple.desktopservices DSDontWriteNetworkStores -bool true
safe_defaults_write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Icon arrangement
safe_plistbuddy "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" "$HOME/Library/Preferences/com.apple.finder.plist"
safe_plistbuddy "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" "$HOME/Library/Preferences/com.apple.finder.plist"
safe_plistbuddy "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" "$HOME/Library/Preferences/com.apple.finder.plist"

# Column view by default
safe_defaults_write com.apple.finder FXPreferredViewStyle -string "clmv"

# Disable empty trash warning
safe_defaults_write com.apple.finder WarnOnEmptyTrash -bool false

# Show path bar, status bar; hide recent tags
safe_defaults_write com.apple.finder ShowPathbar -bool true
safe_defaults_write com.apple.finder ShowStatusBar -bool true
safe_defaults_write com.apple.finder ShowRecentTags -bool false

# Show full POSIX path in Finder title bar
safe_defaults_write com.apple.finder _FXShowPosixPathInTitle -bool true

###############################################################################
# Dock & Hot Corners
###############################################################################
print_info "Configuring Dock..."

safe_defaults_write com.apple.dock orientation -string "left"
safe_defaults_write com.apple.dock tilesize -int 30
safe_defaults_write com.apple.dock mineffect -string "scale"
safe_defaults_write com.apple.dock autohide -bool true
safe_defaults_write com.apple.dock autohide-delay -float 0
safe_defaults_write com.apple.dock autohide-time-modifier -float 0
safe_defaults_write com.apple.dock enable-spring-load-actions-on-all-items -bool true
safe_defaults_write com.apple.dock show-recents -bool false

# Minimize windows into application icon
safe_defaults_write com.apple.dock minimize-to-application -bool true

# Disable all hot corners (0 = no action)
safe_defaults_write com.apple.dock wvous-tl-corner -int 0
safe_defaults_write com.apple.dock wvous-tr-corner -int 0
safe_defaults_write com.apple.dock wvous-bl-corner -int 0
safe_defaults_write com.apple.dock wvous-br-corner -int 0
safe_defaults_write com.apple.dock wvous-tl-modifier -int 0
safe_defaults_write com.apple.dock wvous-tr-modifier -int 0
safe_defaults_write com.apple.dock wvous-bl-modifier -int 0
safe_defaults_write com.apple.dock wvous-br-modifier -int 0

###############################################################################
# Window Manager (Sequoia/Tahoe tiling)
###############################################################################
print_info "Configuring Window Manager..."

# Remove margin between tiled windows
safe_defaults_write com.apple.WindowManager EnableTiledWindowMargins -bool false

###############################################################################
# Photos
###############################################################################
print_info "Disabling Photos auto-launch on device connect..."
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true 2>/dev/null \
  && print_success "Photos auto-launch disabled" \
  || print_error "Failed to disable Photos auto-launch"

###############################################################################
# Activity Monitor
###############################################################################
print_info "Configuring Activity Monitor..."
safe_defaults_write com.apple.ActivityMonitor ShowCategory -int 0
safe_defaults_write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
safe_defaults_write com.apple.ActivityMonitor SortDirection -int 0
# Show Dock icon with CPU usage
safe_defaults_write com.apple.ActivityMonitor IconType -int 5

###############################################################################
# TextEdit
###############################################################################
print_info "Configuring TextEdit..."
# Use plain text by default
safe_defaults_write com.apple.TextEdit RichText -int 0
# Open and save files as UTF-8
safe_defaults_write com.apple.TextEdit PlainTextEncoding -int 4
safe_defaults_write com.apple.TextEdit PlainTextEncodingForWrite -int 4

###############################################################################
# Disk Utility
###############################################################################
# Show all devices (not just volumes)
safe_defaults_write com.apple.DiskUtility SidebarShowAllDevices -bool true
safe_defaults_write com.apple.DiskUtility DUDebugMenuEnabled -bool true
safe_defaults_write com.apple.DiskUtility advanced-image-options -bool true

###############################################################################
# Software Update
###############################################################################
print_info "Configuring Software Update..."
# Enable automatic checks and critical updates
safe_defaults_write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
safe_defaults_write com.apple.SoftwareUpdate AutomaticDownload -int 1
safe_defaults_write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
# Note: ScheduleFrequency is deprecated since Catalina and has no effect.
# Note: com.apple.commerce AutoUpdate is effectively deprecated in Sequoia+.

###############################################################################
# Safari (requires Full Disk Access for Terminal)
# Note: In Sequoia+, some Safari prefs moved to com.apple.Safari.SandboxBroker.
# We write to both domains for compatibility across macOS versions.
###############################################################################
print_info "Configuring Safari..."
safe_defaults_write com.apple.Safari SearchProviderIdentifier -string "com.ecosia"
safe_defaults_write com.apple.Safari PreloadTopHit -bool false
safe_defaults_write com.apple.Safari WarnAboutFraudulentWebsites -bool true
safe_defaults_write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
safe_defaults_write com.apple.Safari SafariGeolocationPermissionPolicy -int 0
safe_defaults_write com.apple.Safari TargetedClicksCreateTabs -bool true
safe_defaults_write com.apple.Safari ShowFullURLInSmartSearchField -bool true
safe_defaults_write com.apple.Safari SendDoNotTrackHTTPHeader -bool true

# AutoOpenSafeDownloads moved to SandboxBroker in Sequoia
safe_defaults_write com.apple.Safari AutoOpenSafeDownloads -bool false
safe_defaults_write com.apple.Safari.SandboxBroker AutoOpenSafeDownloads -bool false

###############################################################################
# Mail
###############################################################################
print_info "Configuring Mail..."
# Copy addresses as "foo@bar.com" instead of "Foo Bar <foo@bar.com>"
safe_defaults_write com.apple.mail AddressesIncludeNameOnPasteboard -bool false
# Disable inline attachment viewing
safe_defaults_write com.apple.mail DisableInlineAttachmentViewing -bool true

###############################################################################
# Wallpaper
###############################################################################
print_info "Setting default wallpaper..."
WALLPAPER_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/wallpaper/default.jpeg"
if [[ -f "$WALLPAPER_PATH" ]]; then
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$WALLPAPER_PATH\"" \
    && print_success "Wallpaper set" \
    || print_error "Failed to set wallpaper"
else
  print_info "Wallpaper file not found at $WALLPAPER_PATH - skipping"
fi

###############################################################################
# Spotlight
###############################################################################
ask_for_confirmation "Rebuild Spotlight index? (takes a while)"
if answer_is_yes; then
  print_info "Rebuilding Spotlight index..."
  if sudo mdutil -E / &>/dev/null; then
    print_success "Spotlight reindex triggered"
  else
    print_error "Spotlight reindex failed"
  fi
else
  print_info "Skipped Spotlight rebuild"
fi

###############################################################################
# Restart affected apps
###############################################################################
print_info "Restarting affected applications..."
for app in "Activity Monitor" "cfprefsd" "Dock" "Finder" "Messages" "Photos" "SystemUIServer"; do
  safe_killall "$app"
done

print_success "macOS configuration complete!"
print_info "Some changes require a logout/restart to take full effect."
