#!/usr/bin/env bash
set -euo pipefail

# Install the pinned agent-rack runtime and the version-specific OpenCode guard.
# The Infra harness package owns every private harness configuration, profile,
# skill, and root-rule update. This wrapper does not maintain local overlays.

: "${ROOT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT_DIR/core/functions.sh"

CHECK_SOURCE_ONLY=false
if [[ "${1:-}" == "--check-source" ]]; then
  CHECK_SOURCE_ONLY=true
elif [[ $# -ne 0 ]]; then
  print_error "Unknown argument '$1'. Use: --check-source."
  exit 1
fi

# An explicit environment source wins over config.properties. Preserve the old
# policy-source setting only as a migration input; its parent is the harness
# checkout, never a source of copied configuration.
INFRA_HARNESS_SOURCE_OVERRIDE="${INFRA_HARNESS_SOURCE:-}"
LEGACY_POLICY_SOURCE_OVERRIDE="${AGENT_RACK_POLICY_SOURCE:-}"
CONFIG_FILE="$ROOT_DIR/utils/config.properties"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  print_info "Configuration loaded from config.properties"
else
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

DEFAULT_INFRA_HARNESS_SOURCE="$HOME/Netzlaufwerke/developer/repos/infra/infra"
if [[ -z "$INFRA_HARNESS_SOURCE_OVERRIDE" && -n "$LEGACY_POLICY_SOURCE_OVERRIDE" ]]; then
  case "$LEGACY_POLICY_SOURCE_OVERRIDE" in
    */stacks/t3code/agent-rack-policies) INFRA_HARNESS_SOURCE="${LEGACY_POLICY_SOURCE_OVERRIDE%/stacks/t3code/agent-rack-policies}" ;;
  esac
fi
INFRA_HARNESS_SOURCE="${INFRA_HARNESS_SOURCE_OVERRIDE:-${INFRA_HARNESS_SOURCE:-$DEFAULT_INFRA_HARNESS_SOURCE}}"
# Compatibility only. Do not use this value to copy or edit policy files.
AGENT_RACK_POLICY_SOURCE="$INFRA_HARNESS_SOURCE/stacks/t3code/agent-rack-policies"

resolve_harness_package() {
  local cached_link="$HOME/.local/share/infra-harness/current"
  local cache_root="$HOME/.local/share/infra-harness"
  local cached="$cached_link"
  if [[ -d "$cached_link" ]]; then
    cached="$(cd -P "$cached_link" && pwd)"
  fi
  if [[ -f "$INFRA_HARNESS_SOURCE/scripts/install-local-harness.py" && -f "$INFRA_HARNESS_SOURCE/scripts/build-harness-release.py" ]]; then
    # A live checkout is trusted only after its published bundle can be built,
    # sealed, verified, and read. This catches incomplete checkouts before a
    # private-state pull mounts the share.
    local build_parent built runtime_lock build_result build_digest
    build_parent="$(mktemp -d "${TMPDIR:-/tmp}/infra-harness-check.XXXXXX")" || return 1
    built="$build_parent/release"
    if ! build_result="$(python3 "$INFRA_HARNESS_SOURCE/scripts/build-harness-release.py" "$built")" ||
       ! build_digest="$(python3 - "$build_result" <<'PY'
import json, re, sys
value = json.loads(sys.argv[1])
digest = value.get('revision')
if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
    raise SystemExit(1)
print(digest)
PY
)" ||
       ! python3 "$built/scripts/harness-bundle.py" verify "$built" --expected "$build_digest" >/dev/null ||
       ! AGENT_RACK_VERSION="$(read_runtime_lock "$built/agent-rack/agent-rack-runtime.lock.json")"; then
      rm -rf "$build_parent"
      print_error "Live Infra harness source failed complete bundle preflight: $INFRA_HARNESS_SOURCE"
      return 1
    fi
    rm -rf "$build_parent"
    HARNESS_INSTALLER="$INFRA_HARNESS_SOURCE/scripts/install-local-harness.py"
    HARNESS_INSTALL_ARGS=(--adopt)
    HARNESS_SOURCE_LABEL="$INFRA_HARNESS_SOURCE"
    return 0
  fi
  cache_root="$(cd -P "$cache_root" 2>/dev/null && pwd)" || cache_root=""
  local cache_digest="${cached##*/}"
  if [[ -n "$cache_root" && "${cached%/*}" == "$cache_root/releases" && "$cache_digest" =~ ^[0-9a-f]{64}$ && -f "$cached/scripts/apply-harness.py" && -f "$cached/scripts/harness-bundle.py" && -f "$cached/.bundle-manifest.json" && -f "$cached/agent-rack/agent-rack-runtime.lock.json" ]]; then
    local expected_digest="$cache_digest"
    if ! python3 "$cached/scripts/harness-bundle.py" verify "$cached" --expected "$expected_digest" >/dev/null; then
      print_error "Cached Infra harness release failed manifest verification: $cached"
      return 1
    fi
    AGENT_RACK_VERSION="$(read_runtime_lock "$cached/agent-rack/agent-rack-runtime.lock.json")" || {
      print_error "Cached Infra harness runtime lock is invalid: $cached"
      return 1
    }
    HARNESS_INSTALLER="$cached/scripts/apply-harness.py"
    HARNESS_INSTALL_ARGS=(--scope user --adopt)
    HARNESS_SOURCE_LABEL="$cached (verified installed release)"
    return 0
  fi
  print_error "No authoritative Infra harness package is available."
  print_info "Expected checkout: $INFRA_HARNESS_SOURCE"
  print_info "Expected verified release: $cached_link"
  print_info "Provide INFRA_HARNESS_SOURCE or install a verified Infra harness release first."
  return 1
}

read_runtime_lock() {
  node - "$1" <<'NODE'
const fs = require("fs");
const lock = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const version = lock.version;
if (typeof version !== "string" || !/^\d+\.\d+\.\d+$/.test(version)) {
  throw new Error("agent-rack runtime lock has no pinned semantic version in version");
}
process.stdout.write(version);
NODE
}

resolve_harness_package

if [[ "$CHECK_SOURCE_ONLY" == true ]]; then
  print_success "Authoritative Infra harness source is available: $HARNESS_SOURCE_LABEL"
  exit 0
fi

if ! command_exists npm; then
  print_error "npm not found — install Node (02-homebrew.sh) first."
  exit 1
fi
npm_major="$(node -p 'process.versions.node.split(".")[0]')"
if (( npm_major < 20 )); then
  print_error "agent-rack requires Node >= 20 (found $(node --version))."
  exit 1
fi
# Preserve the pinned upstream binary installation. The Infra installer owns
# its registration and every client-side configuration change.
installed="$(npm ls -g agent-rack --depth=0 --parseable 2>/dev/null | tail -1 || true)"
if [[ -n "$installed" && -f "$installed/package.json" ]]; then
  current="$(node -p "require('$installed/package.json').version")"
else
  current=""
fi
if [[ "$current" == "$AGENT_RACK_VERSION" ]]; then
  print_success "agent-rack@$AGENT_RACK_VERSION already installed"
elif [[ -n "$current" ]]; then
  print_error "agent-rack@$current is installed, but the harness requires $AGENT_RACK_VERSION."
  print_info "Update the runtime as a separate, approved prerequisite; restore will not replace a working npm runtime."
  exit 1
else
  print_info "Installing agent-rack@$AGENT_RACK_VERSION (was: ${current:-none})"
  npm install -g "agent-rack@${AGENT_RACK_VERSION}" --no-fund --no-audit
  print_success "Installed agent-rack@$AGENT_RACK_VERSION"
fi

# Keep the OpenCode workaround restorable. It bypasses only 1.18.30.
OPENCODE_WRAPPER_SOURCE="$ROOT_DIR/utils/opencode-wrapper.sh"
OPENCODE_WRAPPER_TARGET="$HOME/.local/bin/opencode"
OPENCODE_STABLE_VERSION="1.18.20"
OPENCODE_STABLE_SHA256="b483e547c029b4f0ba381f0d0c5b420bec48c24c2bbec1fb7f22252bae83da46"
OPENCODE_STABLE_DIR="$HOME/.local/share/opencode/$OPENCODE_STABLE_VERSION"
OPENCODE_STABLE_BIN="$OPENCODE_STABLE_DIR/opencode"
OPENCODE_BREW_BIN="/opt/homebrew/opt/opencode/bin/opencode"
OPENCODE_BREW_VERSION=""
if [[ -x "$OPENCODE_BREW_BIN" ]]; then OPENCODE_BREW_VERSION="$($OPENCODE_BREW_BIN --version 2>/dev/null || true)"; fi
[[ ! -L "$OPENCODE_WRAPPER_TARGET" ]] || { print_error "Refusing symbolic-link OpenCode wrapper target"; exit 1; }
wrapper_rollback="$(mktemp -d "${TMPDIR:-/tmp}/infra-harness-wrapper.XXXXXX")"
wrapper_existed=false
if [[ -e "$OPENCODE_WRAPPER_TARGET" ]]; then
  cp -p "$OPENCODE_WRAPPER_TARGET" "$wrapper_rollback/opencode"
  wrapper_existed=true
fi
rollback_wrapper() {
  if [[ "$wrapper_existed" == true ]]; then
    [[ ! -L "$OPENCODE_WRAPPER_TARGET" ]] || return 1
    cp -p "$wrapper_rollback/opencode" "$OPENCODE_WRAPPER_TARGET" || return 1
  else
    [[ ! -L "$OPENCODE_WRAPPER_TARGET" ]] && rm -f "$OPENCODE_WRAPPER_TARGET"
  fi
  rm -rf "$wrapper_rollback"
  wrapper_rollback=""
}
finish_wrapper() {
  local status="$?"
  trap - EXIT
  if [[ -n "$wrapper_rollback" && -d "$wrapper_rollback" ]]; then
    if [[ "$status" != 0 ]]; then
      rollback_wrapper || { print_error "Wrapper rollback failed; retain $wrapper_rollback"; status=1; }
    else
      rm -rf "$wrapper_rollback"
    fi
  fi
  [[ -z "${download_dir:-}" ]] || rm -rf "$download_dir"
  exit "$status"
}
trap finish_wrapper EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if [[ ! -x "$OPENCODE_STABLE_BIN" && "$OPENCODE_BREW_VERSION" == 1.18.30* ]] || [[ ! -x "$OPENCODE_STABLE_BIN" && ! -x "$OPENCODE_BREW_BIN" ]]; then
  if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then print_error "OpenCode $OPENCODE_STABLE_VERSION fallback needs a macOS arm64 binary"; exit 1; fi
  download_dir="$(mktemp -d "${TMPDIR:-/tmp}/opencode-stable.XXXXXX")"
  archive="$download_dir/opencode-darwin-arm64.zip"; unpacked="$download_dir/unpacked"
  cleanup_download() { rm -rf "$download_dir"; download_dir=""; }
  curl -fsSL --max-time 120 "https://github.com/anomalyco/opencode/releases/download/v$OPENCODE_STABLE_VERSION/opencode-darwin-arm64.zip" -o "$archive"
  actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual_sha256" == "$OPENCODE_STABLE_SHA256" ]] || { print_error "OpenCode fallback checksum mismatch"; exit 1; }
  mkdir -p "$unpacked" "$OPENCODE_STABLE_DIR"; unzip -q "$archive" -d "$unpacked"; install -m 0755 "$unpacked/opencode" "$OPENCODE_STABLE_BIN"
  print_success "installed verified OpenCode $OPENCODE_STABLE_VERSION fallback"; cleanup_download
fi
ensure_directory "$(dirname "$OPENCODE_WRAPPER_TARGET")" false
if ! cmp -s "$OPENCODE_WRAPPER_SOURCE" "$OPENCODE_WRAPPER_TARGET"; then
  if [[ -e "$OPENCODE_WRAPPER_TARGET" ]]; then cp "$OPENCODE_WRAPPER_TARGET" "$OPENCODE_WRAPPER_TARGET.backup.$(date +%Y%m%d_%H%M%S)"; print_info "Backed up $(basename "$OPENCODE_WRAPPER_TARGET")"; fi
  install -m 0755 "$OPENCODE_WRAPPER_SOURCE" "$OPENCODE_WRAPPER_TARGET"; print_success "installed idempotent OpenCode version guard"
else
  print_info "OpenCode version guard already current"
fi

# This is the only private-harness configuration writer in this script.
# The installer transaction owns managed configuration rollback.
# This wrapper restores its OpenCode launcher if that transaction fails.
if ! python3 "$HARNESS_INSTALLER" --help >/dev/null; then
  rollback_wrapper
  print_error "Infra harness installer preflight failed: $HARNESS_INSTALLER"
  exit 1
fi
if ! python3 "$HARNESS_INSTALLER" "${HARNESS_INSTALL_ARGS[@]}"; then
  rollback_wrapper
  print_error "Infra harness installer failed; restored the previous OpenCode wrapper."
  exit 1
fi
rm -rf "$wrapper_rollback"
wrapper_rollback=""
print_success "Infra harness from $HARNESS_SOURCE_LABEL applied with agent-rack@$AGENT_RACK_VERSION"
