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
# agent-rack itself is upstream software: this script only pins a version,
# deploys the shared config, reconciles the managed root-policy block, and
# calls stock commands — nothing custom is layered on top. Safe to re-run;
# all steps are idempotent.

: "${ROOT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT_DIR/core/functions.sh"

CONFIG_FILE="$ROOT_DIR/utils/config.properties"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  print_info "Configuration loaded from config.properties"
else
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

AGENT_RACK_VERSION="${AGENT_RACK_VERSION:-0.12.1}"
AGENT_RACK_MAX_CONCURRENT_SESSIONS="${AGENT_RACK_MAX_CONCURRENT_SESSIONS:-6}"
AGENT_RACK_DEFAULT_TIMEOUT_SECONDS="${AGENT_RACK_DEFAULT_TIMEOUT_SECONDS:-43200}"
# Workspaces the rack may operate in (stock security.allowedWorkspaces).
# Colon-separated; default covers the usual repos, extend for additional trees.
AGENT_RACK_ALLOWED_WORKSPACES="${AGENT_RACK_ALLOWED_WORKSPACES:-$HOME/Developer}"
# Canonical policy source (infra checkout). Must contain the 9 policy files
# deployed identically to the t3code container. 12-ai-config.sh restores a
# snapshot of the same files to ~/.config/agent-rack/ from the SMB share;
# this script overwrites that snapshot from the live canonical source.
AGENT_RACK_POLICY_SOURCE="${AGENT_RACK_POLICY_SOURCE:-$HOME/Developer/_repos/infra/infra/stacks/t3code/agent-rack-policies}"

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
  print_error "Canonical policy source not found: $AGENT_RACK_POLICY_SOURCE"
  print_info "Clone the infra repository or set AGENT_RACK_POLICY_SOURCE in config.properties."
  exit 1
fi
for f in "${POLICY_FILES[@]}"; do
  if [[ ! -f "$AGENT_RACK_POLICY_SOURCE/$f" ]]; then
    print_error "Policy file '$f' missing in $AGENT_RACK_POLICY_SOURCE"
    exit 1
  fi
done
ensure_directory "$CONFIG_DIR" false
backup_file() { # $1 = path to back up if it exists
  if [[ -e "$1" ]]; then
    cp "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backed up $(basename "$1")"
  fi
}
for f in "${POLICY_FILES[@]}"; do
  if ! cmp -s "$AGENT_RACK_POLICY_SOURCE/$f" "$CONFIG_DIR/$f"; then
    backup_file "$CONFIG_DIR/$f"
    cp "$AGENT_RACK_POLICY_SOURCE/$f" "$CONFIG_DIR/$f"
    print_success "deployed policy file $f"
  else
    print_info "$f already current"
  fi
done
chmod 600 "$CONFIG_JSON"
for f in agent-rack.profiles.json agent-rack.security-overlay.json; do
  chmod 600 "$CONFIG_DIR/$f"
done

# ─────────────────────────────────────────────────────────────────────────────
# 3) Environment overlays on the live user config (~/.config/agent-rack/config.json)
#    Starts from the canonical 27-agent config and applies ONLY the Mac-specific
#    fields; everything else stays byte-equivalent to the container deployment.
# ─────────────────────────────────────────────────────────────────────────────
node - "$CONFIG_JSON" "$AGENT_RACK_POLICY_SOURCE/config.json" \
      "$AGENT_RACK_MAX_CONCURRENT_SESSIONS" \
      "$AGENT_RACK_DEFAULT_TIMEOUT_SECONDS" "$AGENT_RACK_ALLOWED_WORKSPACES" <<'NODE'
const fs = require("fs");
const [file, canonical, maxConcurrent, timeout, workspacesRaw] = process.argv.slice(2);
const allowedWorkspaces = workspacesRaw.split(":").filter(Boolean).map((p) => p.replace(/^~/, process.env.HOME));

// Start from the canonical config so Mac and container share the identical
// agent catalogue; the previous local config is preserved as a .backup file by
// the caller only when the deployed policy file itself changed.
const value = JSON.parse(fs.readFileSync(canonical, "utf8"));

value.transport = "stdio";
value.enableSseSidecar = true; // macOS: OpenCode app connects through the SSE sidecar
value.allowedWorkspaces = allowedWorkspaces.length ? allowedWorkspaces : [process.env.HOME];

// Keep every canonical security field (executionPolicy, sanitizeEnv,
// retention, output caps) and override only the environment-specific knobs.
value.security = {
  ...value.security,
  maxConcurrentSessions: Number(maxConcurrent),
  defaultTimeoutSeconds: Number(timeout),
};

fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
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


def reconcile(path: Path, body: str) -> bool:
    before = path.read_text(encoding="utf-8") if path.exists() else ""
    if before.count(START) != before.count(END):
        raise RuntimeError("malformed managed block in %s" % path)
    if before.count(LEGACY_START) != before.count(LEGACY_END):
        raise RuntimeError("malformed legacy block in %s" % path)
    stripped = BLOCK.sub("", before)
    stripped = LEGACY.sub("", stripped).rstrip()
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
$have_codex    && register codex
$have_cursor   && register cursor --scope user
$have_opencode && register opencode

# Stock guidance skills for the harnesses that support skill directories.
$have_claude   && "$AGENT_RACK_BIN" cp --target claude --scope user   >/dev/null
$have_codex    && "$AGENT_RACK_BIN" cp --target codex --scope user   >/dev/null
$have_cursor   && "$AGENT_RACK_BIN" cp --target cursor --scope user  >/dev/null
$have_opencode && "$AGENT_RACK_BIN" cp --target opencode --scope user >/dev/null
print_success "agent-rack guidance skills ensured"

print_success "agent-rack ($AGENT_RACK_VERSION) ready. Fully quit and reopen desktop apps so they reload MCP configuration."
