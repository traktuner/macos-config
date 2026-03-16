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

  # Run Swift in a subshell so set -e doesn't kill the whole script on failure
  local rc=0
  swift - "$scheme" "$app_path" <<'SWIFT' || rc=$?
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

  if [[ $rc -eq 0 ]]; then
    print_success "$app_name set as default for $scheme"
    return 0
  else
    print_error "Failed to set $app_name as default for $scheme (exit code: $rc)"
    return 1
  fi
}

###############################################################################
# Default Mail App: Proton Mail
###############################################################################
if [[ -d "/Applications/Proton Mail.app" ]]; then
  set_default_app_for_scheme "mailto" "/Applications/Proton Mail.app" "Proton Mail" || true
else
  print_error "Proton Mail not installed — skipping default mail setup"
fi

###############################################################################
# Default Browser: Firefox
# macOS shows a mandatory confirmation dialog for http/https.
# We use 'defaultbrowser' which triggers the dialog, then inform the user.
###############################################################################
if [[ -d "/Applications/Firefox.app" ]]; then
  # Resolve defaultbrowser binary (may not be in PATH if Homebrew was just installed)
  DEFAULTBROWSER=""
  if command_exists defaultbrowser; then
    DEFAULTBROWSER="defaultbrowser"
  elif [[ -x "/opt/homebrew/bin/defaultbrowser" ]]; then
    DEFAULTBROWSER="/opt/homebrew/bin/defaultbrowser"
  elif [[ -x "/usr/local/bin/defaultbrowser" ]]; then
    DEFAULTBROWSER="/usr/local/bin/defaultbrowser"
  fi

  if [[ -n "$DEFAULTBROWSER" ]]; then
    # defaultbrowser sets BOTH http and https in one go — no need for separate https call
    print_info "Setting Firefox as default browser..."
    print_info "macOS will show a confirmation dialog — please click 'Use Firefox'."
    sleep 2
    "$DEFAULTBROWSER" firefox || print_error "defaultbrowser returned an error (dialog may not have been confirmed)"
    print_success "Firefox default browser request sent (confirm the dialog if prompted)"
  else
    # Fallback: use Swift API (also triggers dialog, one for http is enough)
    print_info "macOS will show a confirmation dialog — please click 'Use Firefox'."
    sleep 2
    set_default_app_for_scheme "http" "/Applications/Firefox.app" "Firefox" || true
  fi
else
  print_error "Firefox not installed — skipping default browser setup"
fi
