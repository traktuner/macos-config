#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Installing apps not available via Homebrew"

DOWNLOAD_DIR="$(mktemp -d)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

# -- Helper: download and install .pkg
install_pkg() {
  local name="$1" url="$2"
  local pkg_file="$DOWNLOAD_DIR/${name}.pkg"

  if [[ -d "/Applications/${name}.app" ]] || pkgutil --pkgs 2>/dev/null | grep -qi "$name"; then
    print_success "$name is already installed"
    return 0
  fi

  print_info "Downloading $name..."
  if curl -fsSL --retry 3 --retry-delay 2 -o "$pkg_file" "$url"; then
    print_info "Installing $name..."
    if sudo installer -pkg "$pkg_file" -target /; then
      print_success "$name installed"
    else
      print_error "Failed to install $name"
    fi
  else
    print_error "Failed to download $name"
  fi
}

# -- Helper: download and install .dmg
install_dmg() {
  local name="$1" url="$2" app_name="${3:-$1}"
  local dmg_file="$DOWNLOAD_DIR/${name}.dmg"

  if [[ -d "/Applications/${app_name}.app" ]]; then
    print_success "$name is already installed"
    return 0
  fi

  print_info "Downloading $name..."
  if curl -fsSL --retry 3 --retry-delay 2 -o "$dmg_file" "$url"; then
    print_info "Mounting $name..."
    local mount_point
    mount_point=$(hdiutil attach "$dmg_file" -nobrowse -quiet | tail -1 | awk '{print $NF}')

    if [[ -z "$mount_point" ]]; then
      # Try alternative parsing
      mount_point=$(hdiutil attach "$dmg_file" -nobrowse -quiet | grep "/Volumes" | sed 's/.*\(\/Volumes\/.*\)/\1/')
    fi

    if [[ -d "$mount_point" ]]; then
      # Find .app in the mounted volume
      local app_path
      app_path=$(find "$mount_point" -maxdepth 2 -name "*.app" -type d | head -1)

      if [[ -n "$app_path" ]]; then
        print_info "Copying $name to /Applications..."
        if cp -R "$app_path" /Applications/; then
          print_success "$name installed"
        else
          print_error "Failed to copy $name to /Applications"
        fi
      else
        # Maybe it has a .pkg inside the DMG
        local pkg_path
        pkg_path=$(find "$mount_point" -maxdepth 2 -name "*.pkg" -type f | head -1)
        if [[ -n "$pkg_path" ]]; then
          print_info "Found .pkg inside DMG, installing..."
          if sudo installer -pkg "$pkg_path" -target /; then
            print_success "$name installed"
          else
            print_error "Failed to install $name from .pkg"
          fi
        else
          print_error "No .app or .pkg found in $name DMG"
        fi
      fi

      hdiutil detach "$mount_point" -quiet 2>/dev/null || true
    else
      print_error "Failed to mount $name DMG"
    fi
  else
    print_error "Failed to download $name"
  fi
}

###############################################################################
# UrBackup Client (.pkg)
###############################################################################
ask_for_confirmation "Install UrBackup Client?"
if answer_is_yes; then
  install_pkg "UrBackup Client" "https://hndl.urbackup.org/Client/2.5.29/UrBackup%20Client%202.5.29.pkg"
fi

