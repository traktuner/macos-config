#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"

print_info "Running PRE-FLIGHT tasks: snapshot, CrashPlan & toggleAirport"

# Track snapshot for potential rollback
SNAPSHOT_CREATED=false
SNAPSHOT_NAME=""

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup Trap - logs snapshot info for potential rollback
# ─────────────────────────────────────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [[ "$SNAPSHOT_CREATED" == "true" ]]; then
    print_info "Time Machine snapshot created: $SNAPSHOT_NAME"
    print_info "To restore: tmutil restore -s \"$SNAPSHOT_NAME\" /"
  fi
  
  if [[ $exit_code -eq 0 ]]; then
    print_success "Pre-flight tasks completed successfully"
  else
    print_error "Pre-flight tasks failed with exit code: $exit_code"
  fi
  
  exit $exit_code
}

trap cleanup EXIT INT TERM HUP

# 0) Snapshot - Create a safety snapshot before making changes
print_info "Creating Time Machine local snapshot..."
print_info "This snapshot will allow you to rollback all changes if needed"
if tm_snapshot; then
  SNAPSHOT_CREATED=true
  SNAPSHOT_NAME=$(tmutil listlocalsnapshots / | tail -1 | sed 's/Snapshot: //')
  print_info "Snapshot name: $SNAPSHOT_NAME"
  print_info "To list all snapshots later: tmutil listlocalsnapshots /"
else
  print_info "Snapshot failed - continuing without rollback point"
fi

# 1) CrashPlan
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP_DIR="/Library/Application Support/CrashPlan"
ensure_directory "$CP_DIR" true

SOURCE_CFG="$SCRIPT_DIR/deploy.properties"
if [[ -f "$SOURCE_CFG" ]]; then
  print_info "Copying deploy.properties..."
  sudo cp "$SOURCE_CFG" "$CP_DIR/" && print_success "Copied deploy.properties" \
    || { print_error "Failed to copy deploy.properties"; exit 1; }
else
  print_error "deploy.properties not found at $SOURCE_CFG"
  exit 1
fi

# 2) toggleAirport - auto-disable Wi-Fi when Ethernet is connected
#    Script is self-installing: it generates its own LaunchDaemon plist with
#    LaunchEvents/notifyd trigger (replaces old WatchPaths which didn't work on Tahoe)
TOGGLER="/Library/Scripts/toggleAirport.sh"

print_info "Installing toggleAirport..."
download_file "https://gist.githubusercontent.com/traktuner/8431e9daf006c0c1d246b8a4766f15b4/raw/toggleAirport.sh" "$TOGGLER" 755 true
sudo chown root:wheel "$TOGGLER"

# Self-install: generates plist + loads LaunchDaemon
sudo "$TOGGLER" on

print_success "Pre-flight tasks complete"
