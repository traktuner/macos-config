#!/usr/bin/env bash
set -euo pipefail

# Load shared functions
source "$ROOT_DIR/core/functions.sh"

print_info "Running PRE-FLIGHT tasks: tmutil snapshot, CrashPlan & toggleAirport…"

# ─────────────────────────────────────────────────────────────────────────────
# 0) CREATE A TMUTIL LOCAL SNAPSHOT
# ─────────────────────────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
SNAPSHOT_NAME="preflight-${TIMESTAMP}"
SNAPSHOT_FILE="/tmp/preflight_snapshot_name"

print_info "Creating Time Machine local snapshot named '$SNAPSHOT_NAME'…"
if sudo tmutil localsnapshot --name "$SNAPSHOT_NAME"; then
  print_success "Local snapshot created: $SNAPSHOT_NAME"
  echo "$SNAPSHOT_NAME" > "$SNAPSHOT_FILE"
else
  print_error "Failed to create tmutil local snapshot"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 1) CRASHPLAN CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP_TARGET_DIR="/Library/Application Support/CrashPlan"
CP_SOURCE_CFG="$SCRIPT_DIR/deploy.properties"

print_info "Ensuring CrashPlan support folder exists…"
sudo mkdir -p "$CP_TARGET_DIR" \
  && print_success "OK: $CP_TARGET_DIR" \
  || { print_error "Could not create $CP_TARGET_DIR"; exit 1; }

if [[ -f "$CP_SOURCE_CFG" ]]; then
  print_info "Copying deploy.properties to CrashPlan folder…"
  sudo cp "$CP_SOURCE_CFG" "$CP_TARGET_DIR/" \
    && print_success "deploy.properties copied" \
    || { print_error "Failed to copy deploy.properties"; exit 1; }
else
  print_error "deploy.properties not found at $CP_SOURCE_CFG"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2) TOGGLEAIRPORT SETUP
# ─────────────────────────────────────────────────────────────────────────────
TOGGLER_SCRIPT="/Library/Scripts/toggleAirport.sh"
PLIST_DEST="/Library/LaunchAgents/com.mine.toggleairport.plist"

print_info "Installing toggleAirport script…"
sudo mkdir -p "/Library/Scripts" \
  && print_success "Ensured /Library/Scripts exists" \
  || { print_error "Could not create /Library/Scripts"; exit 1; }

if sudo curl -fsSL \
     "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/toggleAirport.sh" \
     -o "$TOGGLER_SCRIPT"; then
  print_success "Downloaded toggleAirport.sh"
else
  print_error "Failed to download toggleAirport.sh"
  exit 1
fi

sudo chmod 755 "$TOGGLER_SCRIPT" \
  && print_success "Set executable permissions on toggleAirport.sh" \
  || { print_error "Failed to chmod toggleAirport.sh"; exit 1; }

print_info "Installing toggleAirport LaunchAgent plist…"
sudo mkdir -p "/Library/LaunchAgents" \
  && print_success "Ensured /Library/LaunchAgents exists" \
  || { print_error "Could not create /Library/LaunchAgents"; exit 1; }

if sudo curl -fsSL \
     "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/com.mine.toggleairport.plist" \
     -o "$PLIST_DEST"; then
  print_success "Downloaded LaunchAgent plist"
else
  print_error "Failed to download LaunchAgent plist"
  exit 1
fi

sudo chmod 600 "$PLIST_DEST" \
  && print_success "Set permissions on LaunchAgent plist" \
  || { print_error "Failed to chmod LaunchAgent plist"; exit 1; }

# Unload any existing agent
sudo launchctl unload "$PLIST_DEST" &>/dev/null || true
# Load the new agent
print_info "Loading toggleAirport LaunchAgent…"
if sudo launchctl load "$PLIST_DEST"; then
  print_success "toggleAirport LaunchAgent loaded"
else
  print_error "Failed to load toggleAirport LaunchAgent"
  exit 1
fi

print_success "PRE-FLIGHT completed successfully. Snapshot name saved to $SNAPSHOT_FILE"
