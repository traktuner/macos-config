#!/usr/bin/env bash
set -euo pipefail

# Install the pinned stock agent-rack MCP server (npm), deploy the canonical
# agent-rack policy set, and register agent-rack with every installed local AI
# harness through agent-rack's OWN official `install`/`cp` commands.
#
# The canonical agent definitions and policies live in the infra repository
# (stacks/t3code/agent-rack-policies/) — the SAME source the t3code container
# deploys from — so Mac and container always run an identical 27-agent set.
# Only environment specifics differ on the Mac: allowed workspaces, session
# concurrency/timeout, and the SSE sidecar flag, taken from config.properties.
#
# agent-rack itself remains upstream software. This script pins its version,
# deploys the shared config, applies one version-gated join patch, reconciles
# the managed root-policy block, and calls stock commands. Safe to re-run;
# all steps are idempotent.

: "${ROOT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT_DIR/core/functions.sh"

# Keep an explicit one-off policy source above config.properties. This is used
# for a safe bootstrap or urgent convergence from a reviewed checkout; the
# persisted value remains the normal default for unattended runs.
AGENT_RACK_POLICY_SOURCE_OVERRIDE="${AGENT_RACK_POLICY_SOURCE:-}"

CONFIG_FILE="$ROOT_DIR/utils/config.properties"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  print_info "Configuration loaded from config.properties"
else
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

AGENT_RACK_VERSION="${AGENT_RACK_VERSION:-0.12.1}"
# Keep one provider slot available for the root; worker waves remain bounded.
AGENT_RACK_MAX_CONCURRENT_SESSIONS="${AGENT_RACK_MAX_CONCURRENT_SESSIONS:-4}"
AGENT_RACK_DEFAULT_TIMEOUT_SECONDS="${AGENT_RACK_DEFAULT_TIMEOUT_SECONDS:-43200}"
# Workspaces the rack may operate in (stock security.allowedWorkspaces).
# Default: empty = take the canonical list from the policy config unchanged
# (universal config; it carries container and Mac repository/worktree paths).
# Colon-separated override for environment-specific additions.
AGENT_RACK_ALLOWED_WORKSPACES="${AGENT_RACK_ALLOWED_WORKSPACES:-}"
# Canonical policy source (infra checkout). A complete restored agent-rack
# directory is a safe bootstrap fallback when the infra checkout is not yet
# present after a Mac reinstall.
AGENT_RACK_POLICY_SOURCE="${AGENT_RACK_POLICY_SOURCE_OVERRIDE:-${AGENT_RACK_POLICY_SOURCE:-$HOME/Netzlaufwerke/developer/repos/infra/infra/stacks/t3code/agent-rack-policies}}"

POLICY_FILES=(
  config.json
  agent-rack.profiles.json
  agent-rack.security-overlay.json
  DELEGATION.md
  WORKER-CONTRACT.txt
  MODEL-CATALOG.json
  RESEARCH.md
  SOURCES.md
  ROOT-BLOCK.md
  agent-rack-join-patch.mjs
  agent-rack-harness-limits.mjs
)

CONFIG_DIR="$HOME/.config/agent-rack"
CONFIG_JSON="$CONFIG_DIR/config.json"

if ! command_exists npm; then
  print_error "npm not found — install Node (02-homebrew.sh) first."
  exit 1
fi

npm_major="$(node -p 'process.versions.node.split(".")[0]')"
if (( npm_major < 20 )); then
  print_error "agent-rack requires Node >= 20 (found $(node --version))."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 1) Pinned package install (idempotent: same version re-installs cleanly)
# ─────────────────────────────────────────────────────────────────────────────
installed="$(npm ls -g agent-rack --depth=0 --parseable 2>/dev/null | tail -1 || true)"
if [[ -n "$installed" && -f "$installed/package.json" ]]; then
  current="$(node -p "require('$installed/package.json').version")"
else
  current=""
fi

if [[ "$current" == "$AGENT_RACK_VERSION" ]]; then
  print_success "agent-rack@$AGENT_RACK_VERSION already installed"
else
  print_info "Installing agent-rack@$AGENT_RACK_VERSION (was: ${current:-none})"
  npm install -g "agent-rack@${AGENT_RACK_VERSION}" --no-fund --no-audit
  print_success "Installed agent-rack@$AGENT_RACK_VERSION"
fi

AGENT_RACK_BIN="$(command -v agent-rack)"

# ─────────────────────────────────────────────────────────────────────────────
# 2) Deploy the canonical policy set from the infra source.
#    The agent catalogue (27 agents) comes from the shared config.json; only
#    the environment-specific fields below are overridden afterwards.
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -d "$AGENT_RACK_POLICY_SOURCE" ]]; then
  if [[ -d "$CONFIG_DIR" ]]; then
    AGENT_RACK_POLICY_SOURCE="$CONFIG_DIR"
    print_info "Infra checkout not present; using the validated restored agent-rack policy"
  else
    print_error "Canonical policy source not found: $AGENT_RACK_POLICY_SOURCE"
    print_info "Restore ~/.config/agent-rack or clone the infra repository first."
    exit 1
  fi
fi
for f in "${POLICY_FILES[@]}"; do
  if [[ ! -f "$AGENT_RACK_POLICY_SOURCE/$f" ]]; then
    print_error "Policy file '$f' missing in $AGENT_RACK_POLICY_SOURCE"
    exit 1
  fi
done
python3 "$ROOT_DIR/utils/validate-agent-rack-policy.py" \
  "$AGENT_RACK_POLICY_SOURCE/config.json" \
  "$AGENT_RACK_POLICY_SOURCE/agent-rack.profiles.json"
print_success "agent-rack universal workspace and profile policy validated"
ensure_directory "$CONFIG_DIR" false
backup_file() { # $1 = path to back up if it exists
  if [[ -e "$1" ]]; then
    cp "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backed up $(basename "$1")"
  fi
}

# Keep the OpenCode workaround in the restorable Mac configuration. The
# wrapper bypasses only the known-bad 1.18.30 release; later Brew releases are
# used automatically. Download the fallback only when Brew currently exposes
# the bad release or when no Brew binary exists.
OPENCODE_WRAPPER_SOURCE="$ROOT_DIR/utils/opencode-wrapper.sh"
OPENCODE_WRAPPER_TARGET="$HOME/.local/bin/opencode"
OPENCODE_STABLE_VERSION="1.18.20"
OPENCODE_STABLE_SHA256="b483e547c029b4f0ba381f0d0c5b420bec48c24c2bbec1fb7f22252bae83da46"
OPENCODE_STABLE_DIR="$HOME/.local/share/opencode/$OPENCODE_STABLE_VERSION"
OPENCODE_STABLE_BIN="$OPENCODE_STABLE_DIR/opencode"
OPENCODE_BREW_BIN="/opt/homebrew/opt/opencode/bin/opencode"
OPENCODE_BREW_VERSION=""
if [[ -x "$OPENCODE_BREW_BIN" ]]; then
  OPENCODE_BREW_VERSION="$($OPENCODE_BREW_BIN --version 2>/dev/null || true)"
fi
if [[ ! -x "$OPENCODE_STABLE_BIN" && "$OPENCODE_BREW_VERSION" == 1.18.30* ]] ||
   [[ ! -x "$OPENCODE_STABLE_BIN" && ! -x "$OPENCODE_BREW_BIN" ]]; then
  if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    print_error "OpenCode $OPENCODE_STABLE_VERSION fallback needs a macOS arm64 binary"
    exit 1
  fi
  download_dir="$(mktemp -d "${TMPDIR:-/tmp}/opencode-stable.XXXXXX")"
  archive="$download_dir/opencode-darwin-arm64.zip"
  unpacked="$download_dir/unpacked"
  cleanup_download() { rm -rf "$download_dir"; }
  trap cleanup_download EXIT
  curl -fsSL --max-time 120 \
    "https://github.com/anomalyco/opencode/releases/download/v$OPENCODE_STABLE_VERSION/opencode-darwin-arm64.zip" \
    -o "$archive"
  actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual_sha256" == "$OPENCODE_STABLE_SHA256" ]] || {
    print_error "OpenCode fallback checksum mismatch"
    exit 1
  }
  mkdir -p "$unpacked" "$OPENCODE_STABLE_DIR"
  unzip -q "$archive" -d "$unpacked"
  install -m 0755 "$unpacked/opencode" "$OPENCODE_STABLE_BIN"
  print_success "installed verified OpenCode $OPENCODE_STABLE_VERSION fallback"
  trap - EXIT
  cleanup_download
fi
ensure_directory "$(dirname "$OPENCODE_WRAPPER_TARGET")" false
if ! cmp -s "$OPENCODE_WRAPPER_SOURCE" "$OPENCODE_WRAPPER_TARGET"; then
  backup_file "$OPENCODE_WRAPPER_TARGET"
  install -m 0755 "$OPENCODE_WRAPPER_SOURCE" "$OPENCODE_WRAPPER_TARGET"
  print_success "installed idempotent OpenCode version guard"
else
  print_info "OpenCode version guard already current"
fi
for f in "${POLICY_FILES[@]}"; do
  # config.json is the universal source plus a deliberate Mac overlay. The
  # Node step below compares and atomically writes its effective Mac form.
  [[ "$f" == "config.json" ]] && continue
  if ! cmp -s "$AGENT_RACK_POLICY_SOURCE/$f" "$CONFIG_DIR/$f"; then
    backup_file "$CONFIG_DIR/$f"
    cp "$AGENT_RACK_POLICY_SOURCE/$f" "$CONFIG_DIR/$f"
    print_success "deployed policy file $f"
  else
    print_info "$f already current"
  fi
done
[[ ! -f "$CONFIG_JSON" ]] || chmod 600 "$CONFIG_JSON"
for f in agent-rack.profiles.json agent-rack.security-overlay.json; do
  chmod 600 "$CONFIG_DIR/$f"
done

# agent-rack 0.12.1 has only detached parallel sessions. Apply the canonical,
# version-gated join patch after every install so a result-dependent parent can
# wait for all workers without an external watcher or an impossible callback.
node "$CONFIG_DIR/agent-rack-join-patch.mjs"
print_success "agent-rack synchronous parallel join patch active"

# ─────────────────────────────────────────────────────────────────────────────
# 3) Environment overlays on the live user config (~/.config/agent-rack/config.json)
#    Starts from the canonical 27-agent config and applies ONLY the Mac-specific
#    fields; everything else stays byte-equivalent to the container deployment.
# ─────────────────────────────────────────────────────────────────────────────
node - "$CONFIG_JSON" "$AGENT_RACK_POLICY_SOURCE/config.json" \
      "$AGENT_RACK_MAX_CONCURRENT_SESSIONS" \
      "$AGENT_RACK_DEFAULT_TIMEOUT_SECONDS" "$AGENT_RACK_ALLOWED_WORKSPACES" <<'NODE'
const fs = require("fs");
const path = require("path");
const [file, canonical, maxConcurrent, timeout, workspacesRaw] = process.argv.slice(2);
// Empty workspacesRaw = use the canonical list unchanged (universal config:
// the canonical file carries the container and Mac repository/worktree roots,
// including /data/t3/worktrees and /Users/thomas/.t3/worktrees).
const allowedWorkspaces = workspacesRaw.split(":").filter(Boolean).map((p) => p.replace(/^~/, process.env.HOME));

// Start from the canonical config so Mac and container share the identical
// agent catalogue. Write only when the resulting bytes differ.
const value = JSON.parse(fs.readFileSync(canonical, "utf8"));

value.transport = "stdio";
value.enableSseSidecar = true; // macOS: OpenCode app connects through the SSE sidecar
if (allowedWorkspaces.length) value.allowedWorkspaces = allowedWorkspaces;

// Keep every canonical security field (executionPolicy, sanitizeEnv,
// retention, output caps) and override only the environment-specific knobs.
value.security = {
  ...value.security,
  maxConcurrentSessions: Number(maxConcurrent),
  defaultTimeoutSeconds: Number(timeout),
};

const rendered = `${JSON.stringify(value, null, 2)}\n`;
let current = "";
try { current = fs.readFileSync(file, "utf8"); } catch (error) {
  if (error.code !== "ENOENT") throw error;
}
if (current !== rendered) {
  const dir = path.dirname(file);
  const staging = fs.mkdtempSync(path.join(dir, ".agent-rack-config-"));
  const temp = path.join(staging, path.basename(file));
  try {
    fs.writeFileSync(temp, rendered, { mode: 0o600 });
    fs.renameSync(temp, file);
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
}
NODE
print_success "agent-rack config (27 canonical agents + Mac overrides) written to $CONFIG_JSON"
"$AGENT_RACK_BIN" config-check >/dev/null
print_success "agent-rack configuration valid"

# ─────────────────────────────────────────────────────────────────────────────
# 4) Reconcile the managed root-policy block into every local harness rule
#    file. Same markers and semantics as the container deployment, so Mac and
#    container harnesses carry the identical delegation policy.
# ─────────────────────────────────────────────────────────────────────────────
python3 - "$CONFIG_DIR/ROOT-BLOCK.md" \
  "$HOME/.config/opencode/AGENTS.md" \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.claude/CLAUDE.md" <<'PYEOF'
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

START = "<!-- t3-docker:agent-rack-policy:start -->"
END = "<!-- t3-docker:agent-rack-policy:end -->"
BLOCK = re.compile(
    r"(?m)^[ \t]*%s[ \t]*\n.*?^[ \t]*%s[ \t]*(?:\n|$)"
    % (re.escape(START), re.escape(END)),
    re.DOTALL,
)
LEGACY_START = "<!-- BEGIN ONCLOUD AGENT-RACK POLICY V1 -->"
LEGACY_END = "<!-- END ONCLOUD AGENT-RACK POLICY V1 -->"
LEGACY = re.compile(
    r"(?m)^[ \t]*%s[ \t]*\n.*?^[ \t]*%s[ \t]*(?:\n|$)"
    % (re.escape(LEGACY_START), re.escape(LEGACY_END)),
    re.DOTALL,
)
CLAUDE_NATIVE_ROUTING = re.compile(
    r"(?ms)^## Execution model[ \t]*\n.*?(?=^## Project traps\b)"
)
CLAUDE_NATIVE_ROUTING_SENTINELS = (
    "The user's primary coding harness is now OpenCode + Lumo Max",
    "`opus-critical-reviewer`",
    "Use parallel Claude subagents",
)
CLAUDE_NATIVE_BUNDLE = re.compile(
    r"(?ms)^## Available local bundle[ \t]*\n.*?(?=^Lead final responses)"
)
CLAUDE_NATIVE_BUNDLE_SENTINELS = (
    "## Available local bundle",
    "The tiered subagents",
    "`opus-critical-reviewer`",
    "`/preflight`",
)


def reconcile(path: Path, body: str) -> bool:
    before = path.read_text(encoding="utf-8") if path.exists() else ""
    if before.count(START) != before.count(END):
        raise RuntimeError("malformed managed block in %s" % path)
    if before.count(LEGACY_START) != before.count(LEGACY_END):
        raise RuntimeError("malformed legacy block in %s" % path)
    stripped = BLOCK.sub("", before)
    stripped = LEGACY.sub("", stripped).rstrip()
    if path.name == "CLAUDE.md" and all(
        sentinel in stripped for sentinel in CLAUDE_NATIVE_ROUTING_SENTINELS
    ):
        stripped = CLAUDE_NATIVE_ROUTING.sub("", stripped, count=1).rstrip()
    if path.name == "CLAUDE.md" and all(
        sentinel in stripped for sentinel in CLAUDE_NATIVE_BUNDLE_SENTINELS
    ):
        stripped = CLAUDE_NATIVE_BUNDLE.sub("", stripped, count=1).rstrip()
    block = "%s\n%s\n%s" % (START, body.rstrip(), END)
    after = "%s\n\n%s\n" % (stripped, block) if stripped else "%s\n" % block
    if after == before:
        return False
    if path.exists():
        mode = stat.S_IMODE(path.stat().st_mode)
        uid = path.stat().st_uid
        gid = path.stat().st_gid
    else:
        mode = 0o644
        uid = gid = None
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(prefix=".%s." % path.name, dir=str(path.parent))
    tmp = Path(tmp_name)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write(after)
        os.chmod(tmp, mode)
        if uid is not None and gid is not None:
            os.chown(tmp, uid, gid)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)
    return True


body = Path(sys.argv[1]).read_text(encoding="utf-8")
if not body.strip():
    sys.exit("root policy body is empty")
failed = False
for arg in sys.argv[2:]:
    target = Path(arg)
    try:
        changed = reconcile(target, body)
    except (OSError, RuntimeError) as exc:
        print("%s: ERROR: %s" % (target, exc))
        failed = True
        continue
    print("%s: changed: %s" % (target, "yes" if changed else "no"))
sys.exit(1 if failed else 0)
PYEOF
print_success "agent-rack root policy block reconciled into local harness files"

# Claude's legacy tier agents bypass the fixed agent-rack catalogue through
# Claude's built-in Agent tool. Keep a recoverable copy outside discovery.
quarantine_claude_native_tier_agents() {
  local source="$HOME/.claude/agents"
  local quarantine="$HOME/.claude/agents-quarantine/agent-rack-native-tier"
  local name destination
  local names=(
    lumo-basic-researcher.md
    lumo-plus-implementer.md
    sonnet-sanity-checker.md
    opus-critical-reviewer.md
    fable-architect.md
  )
  local command_source="$HOME/.claude/commands"
  local command_quarantine="$HOME/.claude/commands-quarantine/agent-rack-native-tier"
  local command_names=(
    codex-impl.md
    codex-review.md
    critical-review.md
    final-review.md
    lumo-impl.md
    lumo-research.md
    lumo-review.md
    preflight.md
    sanity-check.md
  )
  if [[ -d "$source" ]]; then
    for name in "${names[@]}"; do
      [[ -f "$source/$name" ]] || continue
      mkdir -p "$quarantine"
      destination="$quarantine/$name"
      if [[ -e "$destination" ]]; then
        destination="$quarantine/${name%.md}.restored.$(date +%Y%m%d_%H%M%S).md"
      fi
      mv "$source/$name" "$destination"
      print_info "quarantined legacy native Claude agent $name"
    done
  fi

  [[ -d "$command_source" ]] || return 0
  for name in "${command_names[@]}"; do
    [[ -f "$command_source/$name" ]] || continue
    mkdir -p "$command_quarantine"
    destination="$command_quarantine/$name"
    if [[ -e "$destination" ]]; then
      destination="$command_quarantine/${name%.md}.restored.$(date +%Y%m%d_%H%M%S).md"
    fi
    mv "$command_source/$name" "$destination"
    print_info "quarantined legacy Claude routing command $name"
  done
}

quarantine_claude_native_tier_agents

# ─────────────────────────────────────────────────────────────────────────────
# 5) Register with every installed harness via stock, idempotent commands.
#    agent-rack detects the binaries and skips what is not installed.
# ─────────────────────────────────────────────────────────────────────────────
register() { # $1 = target, $2.. = extra args
  local target="$1"; shift
  local out
  if out="$("$AGENT_RACK_BIN" install --target "$target" "$@" 2>&1)"; then
    print_success "agent-rack registered with $target"
  elif echo "$out" | grep -qi "already exists"; then
    # agent-rack's underlying `claude mcp add` exits 1 when the registration
    # is already present — that is the desired steady state, not a failure.
    print_success "agent-rack already registered with $target"
  else
    print_error "agent-rack install --target $target failed: $out"
    return 1
  fi
}

have_claude=false; command_exists claude && have_claude=true
have_codex=false;  command_exists codex  && have_codex=true
have_cursor=false; [[ -d "$HOME/.cursor" ]] && have_cursor=true
have_opencode=false; command_exists opencode && have_opencode=true

$have_claude   && register claude --scope user
# Stock install rewrites existing Codex/OpenCode entries on every run (dropping
# the harness limits below), so register only when the entry is missing.
$have_codex    && { codex mcp get agent-rack >/dev/null 2>&1 || register codex; }
$have_cursor   && register cursor --scope user
# Capture first: `| grep -q` makes opencode die of SIGPIPE, and pipefail then
# reports a missing entry.
$have_opencode && { [[ "$(opencode mcp list 2>/dev/null)" == *agent-rack* ]] || register opencode; }

# Canonical harness limits (same script as the T3 container): 3-hour
# agent-rack MCP tool-call timeout and no native subagent tools.
node "$CONFIG_DIR/agent-rack-harness-limits.mjs" \
  --codex-config "$HOME/.codex/config.toml" \
  --claude-config "$HOME/.claude.json" \
  --claude-settings "$HOME/.claude/settings.json" \
  --opencode-config "$HOME/.config/opencode/opencode.jsonc" \
  --opencode-config "$HOME/.config/opencode/opencode.json"
print_success "agent-rack harness limits reconciled"

# Stock guidance skills for the harnesses that support skill directories.
# `--target codex` is a stock agent-rack trap: version 0.12.1 writes to
# ~/.codex/skills, but Codex discovers ~/.agents/skills. Pass the shared
# Agent Skills directory explicitly so the destination matches discovery.
# Claude skills are restored from the managed Claude source. Do not run the
# stock copier here: it would overwrite the Claude-adapted frontmatter and
# reintroduce duplicate OpenCode skill IDs.
$have_codex    && "$AGENT_RACK_BIN" cp "$HOME/.agents/skills" --scope user >/dev/null
$have_cursor   && "$AGENT_RACK_BIN" cp --target cursor --scope user >/dev/null

# OpenCode already scans ~/.agents/skills and ~/.claude/skills. Remove only
# duplicate IDs from its higher-precedence legacy root. Keep OpenCode-only
# skills. Move duplicates to a recoverable quarantine outside the scan path.
quarantine_opencode_skill_duplicates() {
  local opencode_skills="$HOME/.config/opencode/skills"
  local shared_skills="$HOME/.agents/skills"
  local quarantine="$HOME/.config/opencode/skills-quarantine"
  [[ -d "$opencode_skills" && -d "$shared_skills" ]] || return 0

  local duplicate found=0
  for duplicate in "$opencode_skills"/*; do
    [[ -d "$duplicate" ]] || continue
    [[ -f "$duplicate/SKILL.md" ]] || continue
    local name="$(basename "$duplicate")"
    [[ -f "$shared_skills/$name/SKILL.md" ]] || continue
    found=1
    if [[ -e "$quarantine/$name" ]]; then
      print_error "OpenCode skill quarantine already contains '$name'; refusing to overwrite it"
      return 1
    fi
  done
  (( found == 0 )) && return 0

  mkdir -p "$quarantine"
  for duplicate in "$opencode_skills"/*; do
    [[ -d "$duplicate" && -f "$duplicate/SKILL.md" ]] || continue
    local name="$(basename "$duplicate")"
    [[ -f "$shared_skills/$name/SKILL.md" ]] || continue
    mv "$duplicate" "$quarantine/$name"
    print_info "quarantined duplicate OpenCode skill $name"
  done
}

quarantine_codex_skill_trap() {
  local codex_skills="$HOME/.codex/skills"
  local quarantine="$HOME/.codex/skills-quarantine"
  [[ -d "$codex_skills" ]] || return 0

  local stale found=0
  for stale in "$codex_skills"/agent-rack-*; do
    [[ -d "$stale" ]] || continue
    found=1
    local name="$(basename "$stale")"
    if [[ -e "$quarantine/$name" ]]; then
      print_error "Codex skill quarantine already contains '$name'; refusing to overwrite it"
      return 1
    fi
  done
  (( found == 0 )) && return 0

  mkdir -p "$quarantine"
  for stale in "$codex_skills"/agent-rack-*; do
    [[ -d "$stale" ]] || continue
    local name="$(basename "$stale")"
    mv "$stale" "$quarantine/$name"
    print_info "quarantined stale Codex skill $name"
  done
}

quarantine_nested_skill_entrypoints() {
  local root nested disabled found=0
  for root in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.config/opencode/skills"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r nested; do
      [[ -n "$nested" ]] || continue
      found=1
      disabled="${nested}.disabled"
      if [[ -e "$disabled" ]]; then
        print_error "nested skill entrypoint already has a disabled copy: $disabled"
        return 1
      fi
    done < <(find "$root" -mindepth 3 -type f -name SKILL.md -print)
  done
  (( found == 0 )) && return 0

  for root in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.config/opencode/skills"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r nested; do
      [[ -n "$nested" ]] || continue
      mv "$nested" "${nested}.disabled"
      print_info "disabled nested skill entrypoint $nested"
    done < <(find "$root" -mindepth 3 -type f -name SKILL.md -print)
  done
}

sync_cursor_shared_skills() {
  local source="$HOME/.agents/skills"
  local target="$HOME/.cursor/skills"
  [[ -d "$source" && -d "$HOME/.cursor" ]] || return 0
  mkdir -p "$target"
  rsync -a "$source/" "$target/"
}

quarantine_opencode_skill_duplicates
quarantine_codex_skill_trap
quarantine_nested_skill_entrypoints
sync_cursor_shared_skills
python3 "$ROOT_DIR/utils/validate-harness-sources.py" "$HOME" "$CONFIG_DIR"
print_success "agent-rack guidance skills ensured"

print_success "agent-rack ($AGENT_RACK_VERSION) ready. Fully quit and reopen desktop apps so they reload MCP configuration."
