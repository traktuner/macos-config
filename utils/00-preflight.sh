#!/usr/bin/env bash
set -euo pipefail

# Load shared functions from core
source "$ROOT_DIR/core/functions.sh"

print_info "Running preflight tasks: ensure CrashPlan folder & copy config"

# Determine this script’s directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) Ensure CrashPlan support folder exists
TARGET_DIR="/Library/Application Support/CrashPlan"
if [[ ! -d "$TARGET_DIR" ]]; then
  print_info "Creating '$TARGET_DIR'…"
  sudo mkdir -p "$TARGET_DIR" \
    && print_success "Created '$TARGET_DIR'" \
    || { print_error "Failed to create '$TARGET_DIR'"; exit 1; }
else
  print_success "Folder already exists: '$TARGET_DIR'"
fi

# 2) Copy deploy.properties from this script’s directory
SOURCE_FILE="$SCRIPT_DIR/deploy.properties"
if [[ ! -f "$SOURCE_FILE" ]]; then
  print_error "File not found: $SOURCE_FILE"
  exit 1
fi

print_info "Copying 'deploy.properties' to '$TARGET_DIR'…"
sudo cp "$SOURCE_FILE" "$TARGET_DIR/" \
  && print_success "deploy.properties copied" \
  || { print_error "Failed to copy deploy.properties"; exit 1; }