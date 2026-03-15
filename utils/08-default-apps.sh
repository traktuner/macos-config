#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Configuring default applications"

###############################################################################
# Helper: set default app for a URL scheme using NSWorkspace (macOS 12+)
# Uses Swift so there are zero external dependencies.
# For http/https, macOS will show a confirmation dialog that the user must accept.
# For mailto and other schemes, the change is applied silently.
###############################################################################
set_default_app_for_scheme() {
  local scheme="$1"
  local app_path="$2"
  local app_name="$3"

  if [[ ! -d "$app_path" ]]; then
    print_error "$app_name not found at $app_path — skipping"
    return 1
  fi

  print_info "Setting $app_name as default for $scheme..."

  local result
  result=$(swift - "$scheme" "$app_path" 2>&1 <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: scheme app_path\n", stderr)
    exit(1)
}

let scheme = CommandLine.arguments[1]
let appPath = CommandLine.arguments[2]
let appURL = URL(fileURLWithPath: appPath)
let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

NSWorkspace.shared.setDefaultApplication(
    at: appURL,
    toOpenURLsWithScheme: scheme
) { error in
    if let error = error {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exitCode = 1
    }
    semaphore.signal()
}

_ = semaphore.wait(timeout: .now() + 10)
exit(exitCode)
SWIFT
  )

  if [[ $? -eq 0 ]]; then
    print_success "$app_name set as default for $scheme"
    return 0
  else
    print_error "Failed to set $app_name as default for $scheme: $result"
    return 1
  fi
}

###############################################################################
# Default Mail App: Proton Mail
###############################################################################
if [[ -d "/Applications/Proton Mail.app" ]]; then
  set_default_app_for_scheme "mailto" "/Applications/Proton Mail.app" "Proton Mail"
else
  print_error "Proton Mail not installed — skipping default mail setup"
fi

###############################################################################
# Default Browser: Firefox
# macOS shows a mandatory confirmation dialog for http/https.
# We use 'defaultbrowser' which triggers the dialog, then inform the user.
###############################################################################
if [[ -d "/Applications/Firefox.app" ]]; then
  if command_exists defaultbrowser; then
    print_info "Setting Firefox as default browser..."
    print_info "macOS will show a confirmation dialog — please click 'Use Firefox'."
    # Small delay so the user can read the message
    sleep 2
    defaultbrowser firefox
    print_success "Firefox default browser request sent (confirm the dialog if prompted)"
  else
    # Fallback: use Swift API (also triggers dialog)
    print_info "macOS will show a confirmation dialog — please click 'Use Firefox'."
    sleep 2
    set_default_app_for_scheme "http" "/Applications/Firefox.app" "Firefox"
    set_default_app_for_scheme "https" "/Applications/Firefox.app" "Firefox"
  fi
else
  print_error "Firefox not installed — skipping default browser setup"
fi
