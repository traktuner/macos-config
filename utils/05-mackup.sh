#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Mackup restore & configuration profile"

# ─────────────────────────────────────────────────────────────────────────────
# 1) Bootstrap Homebrew env into this non-interactive Bash
# ─────────────────────────────────────────────────────────────────────────────
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
  export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
else
  print_error "brew not found; aborting"
  exit 1
fi

# Confirm mackup is now on PATH
if ! command -v mackup &>/dev/null; then
  print_error "mackup binary not found even after loading brew shellenv"
  exit 1
fi
print_success "Found mackup at: $(command -v mackup)"

# ─────────────────────────────────────────────────────────────────────────────
# 2) Copy Mackup config from iCloud
# ─────────────────────────────────────────────────────────────────────────────
: "${HOME:?HOME must be set}"
CLOUD="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
SRC="${CLOUD}/.config/mackup/.mackup.cfg"
DST="${HOME}/.mackup.cfg"

print_info "Copying Mackup config to $DST"
if [[ -f "$SRC" ]]; then
  cp "$SRC" "$DST" && print_success "Config copied" \
    || { print_error "Failed to copy Mackup config"; exit 1; }
else
  print_error "No Mackup config found at $SRC"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3) Run the restore
# ─────────────────────────────────────────────────────────────────────────────
print_info "Running 'mackup restore'…"
if mackup restore; then
  print_success "Mackup restore completed"
else
  print_error "Mackup restore failed"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4) Open configuration profile for interactive install
# ─────────────────────────────────────────────────────────────────────────────
PROFILE="${CLOUD}/FamilyConfig.mobileconfig"
if [[ -f "$PROFILE" ]]; then
  print_info "Opening configuration profile…"
  open "$PROFILE" \
    && print_success "Profile opened; please install it in System Settings." \
    || print_error "Failed to open profile"
else
  print_error "No configuration profile found at $PROFILE"
fi
