#!/usr/bin/env bash
set -euo pipefail

# Fast, repeatable pre-reinstall backup and restore. The destination must be
# a mounted local path. Restore never deletes files at the destination.

# Keep the repository portable. Set BACKUP_DESTINATION or pass a destination
# as the second argument when the mounted share uses a different path.
DESTINATION="${BACKUP_DESTINATION:-$HOME/Netzlaufwerke/restore/2026}"
MODE="${1:-backup}"

if [[ "$MODE" == "backup" && -n "${2:-}" ]]; then
  DESTINATION="$2"
fi

if [[ "$MODE" == "backup" ]]; then
  BACKUP_ROOT="$DESTINATION/$(scutil --get ComputerName 2>/dev/null || hostname -s)-$(date +%Y%m%d-%H%M%S)"
elif [[ "$MODE" == "restore" ]]; then
  BACKUP_ROOT="${2:-}"
  if [[ -z "$BACKUP_ROOT" ]]; then
    BACKUP_ROOT="$(find "$DESTINATION" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -1)"
  fi
else
  echo "Usage: $0 [backup] [destination] | $0 restore [backup-directory]" >&2
  exit 2
fi

if [[ "$MODE" == "backup" ]]; then
  if [[ ! -d "$DESTINATION" ]]; then
    echo "Backup destination is not mounted: $DESTINATION" >&2
    exit 1
  fi
  mkdir -p "$BACKUP_ROOT"
  echo "Backup target: $BACKUP_ROOT"
else
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    echo "Backup directory not found: ${BACKUP_ROOT:-<none>}" >&2
    exit 1
  fi
  echo "Restore source: $BACKUP_ROOT"
  read -r -p "Restore files into $HOME? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Restore cancelled."; exit 0; }
fi

copy_path() {
  local source="$1"
  local relative="$2"
  [[ -e "$source" ]] || { echo "Skip missing: $source"; return 0; }
  mkdir -p "$BACKUP_ROOT/$(dirname "$relative")"
  echo "Copying: $source"
  rsync -a --human-readable --info=progress2 --partial \
    --exclude='Caches/' --exclude='cache/' --exclude='DerivedData/' \
    "$source" "$BACKUP_ROOT/$relative"
}

restore_path() {
  local relative="$1"
  local source="$BACKUP_ROOT/$relative"
  local target="$HOME/$relative"
  [[ -e "$source" ]] || { echo "Skip missing in backup: $relative"; return 0; }
  echo "Restoring: $target"
  if [[ -d "$source" ]]; then
    mkdir -p "$target"
    rsync -a --human-readable --info=progress2 --partial "$source/" "$target/"
  else
    mkdir -p "$(dirname "$target")"
    rsync -a --human-readable --info=progress2 --partial "$source" "$target"
  fi
}

copy_system_path() {
  local source="$1"
  local relative="$2"
  [[ -e "$source" ]] || { echo "Skip missing: $source"; return 0; }
  mkdir -p "$BACKUP_ROOT/System/$(dirname "$relative")"
  echo "Copying system path: $source"
  sudo rsync -a --human-readable --info=progress2 --partial \
    --exclude='Caches/' --exclude='cache/' --exclude='DerivedData/' \
    "$source" "$BACKUP_ROOT/System/$relative"
}

restore_system_path() {
  local relative="$1"
  local source="$BACKUP_ROOT/System/$relative"
  local target="/$relative"
  [[ -e "$source" ]] || { echo "Skip missing system path in backup: $relative"; return 0; }
  echo "Restoring system path: $target"
  if [[ -d "$source" ]]; then
    sudo mkdir -p "$target"
    sudo rsync -a --human-readable --info=progress2 --partial "$source/" "$target/"
  else
    sudo mkdir -p "$(dirname "$target")"
    sudo rsync -a --human-readable --info=progress2 --partial "$source" "$target"
  fi
}

if [[ "$MODE" == "restore" ]]; then
  for relative in \
    Desktop \
    Downloads \
    "Library/Application Support/Firefox" \
    "Library/Audio" \
    "Library/Application Support/MobileSync/Backup" \
    "Library/Application Support/LennarDigital" \
    "Library/Application Support/CrossOver/Bottles" \
    "Library/Preferences/com.codeweavers.CrossOver.plist" \
    "Library/Preferences/de.cableguys.kickstart.plist" \
    "Library/Preferences/de.cableguys.kickstart2.plist" \
    "Library/Preferences/com.reFX.plugins.Nexus.plist" \
    "Library/Preferences/com.apple.logic10.plist" \
    "Library/Preferences/com.apple.logic.pro.cs" \
    "Library/Application Support/com.apple.musicapps.content/Logic Pro Library.bookmark" \
    "Library/Developer/Xcode/Archives" \
    "Library/Developer/Xcode/UserData" \
    "Library/MobileDevice/Provisioning Profiles" \
    .ssh .gitconfig .config .zshrc .zprofile; do
    restore_path "$relative"
  done
  restore_system_path "Library/Audio/Presets"
  restore_system_path "Library/Application Support/Logic"
  echo "Restore complete. Signing certificates still require .p12 import."
  exit 0
fi

# User-owned documents and the folders requested by the owner.
copy_path "$HOME/Desktop" Desktop
copy_path "$HOME/Downloads" Downloads
copy_path "$HOME/Library/Application Support/Firefox" "Library/Application Support/Firefox"
copy_path "$HOME/Library/Audio" "Library/Audio"
copy_path "$HOME/Library/Application Support/MobileSync/Backup" "Library/Application Support/MobileSync/Backup"
copy_path "$HOME/Library/Application Support/LennarDigital" "Library/Application Support/LennarDigital"
copy_path "$HOME/Library/Preferences/de.cableguys.kickstart.plist" "Library/Preferences/de.cableguys.kickstart.plist"
copy_path "$HOME/Library/Preferences/de.cableguys.kickstart2.plist" "Library/Preferences/de.cableguys.kickstart2.plist"
copy_path "$HOME/Library/Preferences/com.reFX.plugins.Nexus.plist" "Library/Preferences/com.reFX.plugins.Nexus.plist"
copy_path "$HOME/Library/Preferences/com.apple.logic10.plist" "Library/Preferences/com.apple.logic10.plist"
copy_path "$HOME/Library/Preferences/com.apple.logic.pro.cs" "Library/Preferences/com.apple.logic.pro.cs"
copy_path "$HOME/Library/Application Support/com.apple.musicapps.content/Logic Pro Library.bookmark" "Library/Application Support/com.apple.musicapps.content/Logic Pro Library.bookmark"
copy_system_path "/Library/Audio/Presets" "Library/Audio/Presets"
copy_system_path "/Library/Application Support/Logic" "Library/Application Support/Logic"

# CrossOver data. Bottles are the important part; preferences preserve setup.
copy_path "$HOME/Library/Application Support/CrossOver/Bottles" "Library/Application Support/CrossOver/Bottles"
copy_path "$HOME/Library/Preferences/com.codeweavers.CrossOver.plist" "Library/Preferences/com.codeweavers.CrossOver.plist"

# Xcode data that cannot be recreated from the Xcode app alone.
copy_path "$HOME/Library/Developer/Xcode/Archives" "Library/Developer/Xcode/Archives"
copy_path "$HOME/Library/Developer/Xcode/UserData" "Library/Developer/Xcode/UserData"
copy_path "$HOME/Library/MobileDevice/Provisioning Profiles" "Library/MobileDevice/Provisioning Profiles"

# Project-independent developer configuration and local certificates metadata.
copy_path "$HOME/.ssh" .ssh
copy_path "$HOME/.gitconfig" .gitconfig
copy_path "$HOME/.config" .config
copy_path "$HOME/.zshrc" .zshrc
copy_path "$HOME/.zprofile" .zprofile

# Record installed package lists for review after reinstall.
brew bundle dump --file="$BACKUP_ROOT/Brewfile.before-reinstall" --force 2>/dev/null || true
brew list --formula >"$BACKUP_ROOT/brew-formulae.txt" 2>/dev/null || true
brew list --cask >"$BACKUP_ROOT/brew-casks.txt" 2>/dev/null || true
mas list >"$BACKUP_ROOT/mas-apps.txt" 2>/dev/null || true
security find-identity -v -p codesigning >"$BACKUP_ROOT/codesigning-identities.txt" 2>/dev/null || true

cat >"$BACKUP_ROOT/README.txt" <<EOF
Created: $(date)
Source: $HOME
This backup excludes caches, Xcode DerivedData, and simulator runtimes.
Reinstall Xcode from the Mac App Store, then install Command Line Tools and
restore signing certificates from exported .p12 files if the login keychain
was erased. The source repositories remain on the TrueNAS developer share.
EOF

echo "Backup complete: $BACKUP_ROOT"
