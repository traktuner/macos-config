#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"

print_info "Running PRE-FLIGHT tasks: snapshot, CrashPlan & toggleAirport"

# 0) Snapshot
TIMESTAMP="$(date +%F_%T)"
SNAPSHOT_NAME="preflight-${TIMESTAMP}"
SNAPSHOT_FILE="/tmp/preflight_snapshot_name"
tm_snapshot "$SNAPSHOT_NAME" "$SNAPSHOT_FILE"

# 1) CrashPlan
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP_DIR="/Library/Application Support/CrashPlan"
ensure_directory "$CP_DIR" true

SOURCE_CFG="$SCRIPT_DIR/deploy.properties"
if [[ -f "$SOURCE_CFG" ]]; then
  print_info "Copying deploy.properties…"
  sudo cp "$SOURCE_CFG" "$CP_DIR/" && print_success "Copied deploy.properties" \
    || { print_error "Failed to copy deploy.properties"; exit 1; }
else
  print_error "deploy.properties not found"
  exit 1
fi

# 2) toggleAirport
TOGGLER="/Library/Scripts/toggleAirport.sh"
PLIST="/Library/LaunchAgents/com.mine.toggleairport.plist"
ensure_directory "/Library/Scripts" true
download_file "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/toggleAirport.sh" "$TOGGLER" 755 true

ensure_directory "/Library/LaunchAgents" true
download_file "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/com.mine.toggleairport.plist" "$PLIST" 600 true

bootstrap_launch_agent "$PLIST"
