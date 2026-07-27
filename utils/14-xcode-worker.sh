#!/usr/bin/env bash
set -Eeuo pipefail

: "${ROOT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT_DIR/core/functions.sh"
CONFIG_FILE="$ROOT_DIR/utils/config.properties"
[[ ! -f "$CONFIG_FILE" ]] || source "$CONFIG_FILE"
if [[ "${T3_XCODE_WORKER_ENABLED:-true}" != "true" ]]; then
  print_info "T3 Xcode worker is disabled by configuration"
  exit 0
fi
[[ "$(uname -s)" == "Darwin" ]] || { print_error "The T3 Xcode worker can only be installed on macOS"; exit 1; }
command_exists npm || { print_error "npm is required. Run 02-homebrew.sh after the Brewfile installs Node.js."; exit 1; }
if ! xcode-select -p >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  print_error "Select and initialize a full Xcode installation before installing the T3 Xcode worker."
  exit 1
fi
script_dir="$ROOT_DIR/utils/xcode-worker"
bin_dir="${T3_XCODE_BIN_DIR:-$HOME/.local/bin}"
npm_prefix="${T3_XCODE_NPM_PREFIX:-$HOME/.local/share/t3-xcode-worker/npm}"
version="${T3_XCODEBUILDMCP_VERSION:-2.6.2}"
launch_agents_dir="$HOME/Library/LaunchAgents"
label="at.traktuner.t3-xcode-worker-update"
plist="$launch_agents_dir/$label.plist"
mkdir -p "$bin_dir" "$npm_prefix" "$launch_agents_dir"
install -m 0755 "$script_dir/t3-xcode-worker" "$bin_dir/t3-xcode-worker"
install -m 0755 "$script_dir/t3-xcode-ssh-gate" "$bin_dir/t3-xcode-ssh-gate"
install -m 0755 "$script_dir/update-xcode-worker.sh" "$bin_dir/t3-xcode-worker-update"
installed_version=""
if [[ -r "$npm_prefix/lib/node_modules/xcodebuildmcp/package.json" ]]; then
  installed_version="$(node -p "require(process.argv[1]).version" "$npm_prefix/lib/node_modules/xcodebuildmcp/package.json" 2>/dev/null || true)"
fi
if [[ "$installed_version" == "$version" ]]; then
  print_success "XcodeBuildMCP $version is already installed"
else
  print_info "Installing pinned XcodeBuildMCP $version"
  T3_XCODE_NPM_PREFIX="$npm_prefix" XCODEBUILDMCP_VERSION="$version" "$bin_dir/t3-xcode-worker-update"
fi
escaped_home="${HOME//&/\\&}"
sed -e "s|@@HOME@@|$escaped_home|g" -e "s|@@XCODEBUILDMCP_VERSION@@|$version|g" \
  "$script_dir/xcode-worker-update.plist.template" > "$plist"
chmod 0644 "$plist"
launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl enable "gui/$(id -u)/$label"
if [[ "${T3_XCODE_ENABLE_REMOTE_LOGIN:-false}" == "true" ]]; then
  print_info "Enabling macOS Remote Login for the T3 Xcode worker"
  sudo /usr/sbin/systemsetup -setremotelogin on >/dev/null
else
  print_info "Remote Login was left unchanged (set T3_XCODE_ENABLE_REMOTE_LOGIN=true to manage it here)"
fi
print_success "T3 Xcode worker $version is installed at $bin_dir/t3-xcode-worker"
print_info "Run t3-xcode-auth from the T3 container to install its restricted key and workspace mapping."
