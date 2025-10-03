#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"

print_info "Running PRE-FLIGHT tasks: snapshot, CrashPlan & toggleAirport"

# 0) Snapshot - Create a safety snapshot before making changes
TIMESTAMP="$(date +%F_%T)"
SNAPSHOT_NAME="macos-config-${TIMESTAMP}"
SNAPSHOT_FILE="/tmp/macos_config_snapshot_name"

print_info "Creating Time Machine snapshot: $SNAPSHOT_NAME"
print_info "This snapshot will allow you to rollback all changes if needed"
tm_snapshot "$SNAPSHOT_NAME" "$SNAPSHOT_FILE"

# Display snapshot info
if [[ -f "$SNAPSHOT_FILE" ]]; then
  SNAPSHOT_CREATED=$(cat "$SNAPSHOT_FILE")
  print_success "Safety snapshot created: $SNAPSHOT_CREATED"
  print_info "To restore this snapshot later, run: sudo tmutil restore '$SNAPSHOT_CREATED'"
else
  print_error "Failed to create snapshot"
  exit 1
fi

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
PLIST="/Library/LaunchDaemons/com.mine.toggleairport.plist"
ensure_directory "/Library/Scripts" true
ensure_directory "/Library/LaunchDaemons" true
download_file "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/toggleAirport.sh" "$TOGGLER" 755 true
download_file "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/com.mine.toggleairport.plist" "$PLIST" 644 true
sudo chown root:wheel "$TOGGLER" "$PLIST"
bootstrap_launch_daemon "$PLIST"