#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "macOS system configuration"

# Analytics
safe_defaults_write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false
safe_defaults_write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" ThirdPartyDataSubmit -bool false

# UI/UX
sudo nvram StartupMute=%01
safe_defaults_write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
safe_defaults_write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
safe_defaults_write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"
safe_defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
safe_defaults_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
safe_defaults_write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
safe_defaults_write com.apple.DiskArbitration.diskarbitrationd DADisableEjectNotification -bool true
safe_defaults_write "/Library/Preferences/com.apple.loginwindow" GuestEnabled -bool false

# Input
safe_defaults_write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Screen
safe_defaults_write com.apple.screensaver askForPassword -int 1
safe_defaults_write com.apple.screensaver askForPasswordDelay -int 0
safe_defaults_write com.apple.screencapture location -string "${HOME}/Desktop"
safe_defaults_write com.apple.screencapture disable-shadow -bool true

# Finder
safe_defaults_write com.apple.finder NewWindowTarget -string "PfDe"
safe_defaults_write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Desktop/"
safe_defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
safe_defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false
safe_defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false
safe_defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false
safe_defaults_write com.apple.frameworks.diskimages auto-open-ro-root -bool true
safe_defaults_write com.apple.frameworks.diskimages auto-open-rw-root -bool true
safe_defaults_write com.apple.finder OpenWindowForNewRemovableDisk -bool true
safe_defaults_write NSGlobalDomain com.apple.springing.enabled -bool true
safe_defaults_write NSGlobalDomain com.apple.springing.delay -float 0
safe_defaults_write com.apple.finder _FXSortFoldersFirst -bool true
safe_defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf"
safe_defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false
safe_defaults_write com.apple.desktopservices DSDontWriteNetworkStores -bool true
safe_defaults_write com.apple.desktopservices DSDontWriteUSBStores -bool true

safe_plistbuddy "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" "$HOME/Library/Preferences/com.apple.finder.plist"
safe_plistbuddy "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" "$HOME/Library/Preferences/com.apple.finder.plist"
safe_plistbuddy "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" "$HOME/Library/Preferences/com.apple.finder.plist"

safe_defaults_write com.apple.finder FXPreferredViewStyle -string "clmv"
safe_defaults_write com.apple.finder WarnOnEmptyTrash -bool false
safe_defaults_write com.apple.finder ShowPathbar -bool true
safe_defaults_write com.apple.finder ShowStatusBar -bool true
safe_defaults_write com.apple.finder ShowRecentTags -bool false

# Dock & Hot Corners
safe_defaults_write com.apple.dock orientation -string "left"
safe_defaults_write com.apple.dock tilesize -int 30
safe_defaults_write com.apple.dock mineffect -string "scale"
safe_defaults_write com.apple.dock autohide -bool true
safe_defaults_write com.apple.dock autohide-delay -float 0
safe_defaults_write com.apple.dock autohide-time-modifier -float 0
safe_defaults_write com.apple.dock enable-spring-load-actions-on-all-items -bool true
safe_defaults_write com.apple.dock show-recents -bool false
safe_defaults_write com.apple.dock wvous-tl-corner -int 0
safe_defaults_write com.apple.dock wvous-tr-corner -int 0
safe_defaults_write com.apple.dock wvous-bl-corner -int 0
safe_defaults_write com.apple.dock wvous-br-corner -int 0

# Photos
print_info "Disabling Photos auto-launch"
if defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true; then
  print_success "Photos disabled"
else
  print_error "Failed to disable Photos"
fi

# Activity Monitor
safe_defaults_write com.apple.ActivityMonitor ShowCategory -int 0
safe_defaults_write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
safe_defaults_write com.apple.ActivityMonitor SortDirection -int 0

# App Store
safe_defaults_write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
safe_defaults_write com.apple.SoftwareUpdate ScheduleFrequency -int 1
safe_defaults_write com.apple.SoftwareUpdate AutomaticDownload -int 1
safe_defaults_write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
safe_defaults_write com.apple.commerce AutoUpdate -bool true

# Safari
safe_defaults_write com.apple.Safari SearchProviderIdentifier -string "com.ecosia"
safe_defaults_write com.apple.Safari PreloadTopHit -bool false
safe_defaults_write com.apple.Safari AutoOpenSafeDownloads -bool false
safe_defaults_write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
safe_defaults_write com.apple.Safari WarnAboutFraudulentWebsites -bool true
safe_defaults_write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
safe_defaults_write com.apple.Safari SafariGeolocationPermissionPolicy -int 0
safe_defaults_write com.apple.Safari TargetedClicksCreateTabs -bool true

# Wallpaper
print_info "Setting default wallpaper"
osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$HOME/Library/Mobile Documents/com~apple~CloudDocs/wallpaper/default.jpeg\"" \
  && print_success "Wallpaper set" \
  || print_error "Failed to set wallpaper"

# Spotlight
print_info "Rebuilding Spotlight index"
if sudo mdutil -E /; then print_success "Spotlight reindex triggered"; else print_error "Spotlight reindex failed"; fi

# Restart affected apps
for app in "Activity Monitor" "cfprefsd" "Dock" "Finder" "Messages" "Photos" "diskarbitrationd" "SystemUIServer"; do
  safe_killall "$app"
done
