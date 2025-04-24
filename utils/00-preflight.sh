#!/usr/bin/env bash
set -euo pipefail

# Load shared functions from core
source "$ROOT_DIR/core/functions.sh"

print_info "Running preflight tasks"

# Determine this script’s directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### 1) CrashPlan folder & config ################################################
TARGET_CP_DIR="/Library/Application Support/CrashPlan"
if [[ ! -d "$TARGET_CP_DIR" ]]; then
  print_info "Creating CrashPlan support folder…"
  sudo mkdir -p "$TARGET_CP_DIR" \
    && print_success "Created $TARGET_CP_DIR" \
    || { print_error "Failed to create $TARGET_CP_DIR"; exit 1; }
else
  print_success "CrashPlan folder exists: $TARGET_CP_DIR"
fi

SOURCE_CP_CFG="$SCRIPT_DIR/deploy.properties"
if [[ ! -f "$SOURCE_CP_CFG" ]]; then
  print_error "deploy.properties not found at $SOURCE_CP_CFG"
  exit 1
fi

print_info "Copying deploy.properties to CrashPlan folder…"
sudo cp "$SOURCE_CP_CFG" "$TARGET_CP_DIR/" \
  && print_success "Copied deploy.properties" \
  || { print_error "Failed to copy deploy.properties"; exit 1; }

### 2) toggleAirport service ####################################################

# Paths
TOGGLER_SCRIPT="/Library/Scripts/toggleAirport.sh"
LAUNCH_AGENT_PLIST="/Library/LaunchAgents/com.mine.toggleairport.plist"

# 2a) Install the toggler script
print_info "Installing toggleAirport script…"
sudo mkdir -p "/Library/Scripts" \
  && print_success "Ensured /Library/Scripts exists" \
  || { print_error "Could not create /Library/Scripts"; exit 1; }

if sudo curl -fsSL \
     "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/toggleAirport.sh" \
     -o "$TOGGLER_SCRIPT"; then
  print_success "Downloaded toggleAirport.sh to $TOGGLER_SCRIPT"
else
  print_error "Failed to download toggleAirport.sh"
  exit 1
fi

sudo chmod 755 "$TOGGLER_SCRIPT" \
  && print_success "Set executable permissions on toggleAirport.sh" \
  || { print_error "Failed to chmod toggleAirport.sh"; exit 1; }

# 2b) Install the LaunchAgent plist from Gist
print_info "Installing toggleAirport LaunchAgent plist…"
sudo mkdir -p "/Library/LaunchAgents" \
  && print_success "Ensured /Library/LaunchAgents exists" \
  || { print_error "Could not create /Library/LaunchAgents"; exit 1; }

if sudo curl -fsSL \
     "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/com.mine.toggleairport.plist" \
     -o "$LAUNCH_AGENT_PLIST"; then
  print_success "Downloaded LaunchAgent plist to $LAUNCH_AGENT_PLIST"
else
  print_error "Failed to download LaunchAgent plist"
  exit 1
fi

sudo chmod 600 "$LAUNCH_AGENT_PLIST" \
  && print_success "Set permissions on LaunchAgent plist" \
  || { print_error "Failed to chmod LaunchAgent plist"; exit 1; }

# Unload existing job if loaded
if sudo launchctl unload "$LAUNCH_AGENT_PLIST" &>/dev/null; then
  print_info "Unloaded existing toggleAirport LaunchAgent"
fi

# Load the LaunchAgent
print_info "Loading toggleAirport LaunchAgent…"
if sudo launchctl load "$LAUNCH_AGENT_PLIST"; then
  print_success "toggleAirport LaunchAgent loaded"
else
  print_error "Failed to load toggleAirport LaunchAgent"
  exit 1
fi

print_success "Preflight tasks completed successfully."
