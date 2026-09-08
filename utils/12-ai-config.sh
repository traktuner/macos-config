#!/usr/bin/env bash
set -euo pipefail

# Works both from bootstrap (ROOT_DIR exported) and standalone (e.g. `bash utils/12-ai-config.sh save`)
: "${ROOT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Load shared functions
source "$ROOT_DIR/core/functions.sh"

# Load configuration
CONFIG_FILE="$ROOT_DIR/utils/config.properties"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  print_info "Configuration loaded from config.properties"
else
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# AI tool configs (Claude Code, Codex, OpenCode) from the SMB tresor.
# The configs live on the private share (like the SSH keys), NEVER in this repo.
#
#   Mode:  pull  (default) copy configs FROM the share INTO your machine
#          save            copy your current local configs UP to the share
#          Run from the bootstrap menu = pull. To seed/update the share:
#            bash utils/12-ai-config.sh save
#
# Expected layout on the share (SMB_AI_PATH):
#   <share>/claude/     -> ~/.claude/              (CLAUDE.md, settings.json, agents, commands)
#   <share>/claude-desktop/ -> ~/Library/Application Support/Claude/
#   <share>/codex/      -> ~/.codex/               (config.toml, AGENTS.md, hooks.json, rules, auth.json)
#   <share>/opencode/   -> ~/.config/opencode/     (policy, agents, skills, plugins, tests, tools/watchers)
#                                                  plugins include the local Lumo usage estimator
#                                                  that restores proactive compaction when Lumo omits usage
#   <share>/agent-rack/ -> ~/.config/agent-rack/   (canonical 27-agent config
#                                                  plus the shared policy set
#                                                  from the infra repository;
#                                                  runtime/ holds SSE auth
#                                                  tokens and is deliberately
#                                                  NOT synced)
# Only the curated items below are synced; runtime state/caches/history are ignored.
# ─────────────────────────────────────────────────────────────────────────────

MODE="${1:-pull}"
if [[ "$MODE" != "pull" && "$MODE" != "save" ]]; then
  print_error "Unknown mode '$MODE'. Use: pull (default) or save."
  exit 1
fi

# Configuration (overridable via config.properties)
SMB_SERVER="${SMB_SERVER:-172.16.10.200}"
SMB_AI_PATH="${SMB_AI_PATH:-tom/tresor/ai-config}"
MOUNT_POINT="${SMB_AI_MOUNT_POINT:-/Volumes/ai-config}"
SMB_TIMEOUT="${SMB_TIMEOUT:-30}"

# Curated items per tool (files and directories). Secrets (auth.json, the real
# opencode.jsonc with its apiKey) live only on the trusted share, never in git.
# NOTE: `skills` removed 2026-07 — the installed ~/.claude/skills were retired; syncing them would
# resurrect dead routing. Per-project memory (~/.claude/projects/*/memory) is version-controlled in
# its own git repo, not synced here (the copy_item rm -rf + flat-item model can't carry a nested path).
CLAUDE_TARGET="$HOME/.claude";           CLAUDE_ITEMS=(CLAUDE.md settings.json agents commands)
CLAUDE_DESKTOP_TARGET="$HOME/Library/Application Support/Claude"; CLAUDE_DESKTOP_ITEMS=(claude_desktop_config.json)
CODEX_TARGET="$HOME/.codex";             CODEX_ITEMS=(config.toml AGENTS.md hooks.json rules auth.json)
OPENCODE_TARGET="$HOME/.config/opencode"; OPENCODE_ITEMS=(opencode.jsonc AGENTS.md package.json package-lock.json doctor.sh rules agents commands skills tools plugins tests)
# agent-rack: the canonical 27-agent config plus the shared policy set from
# the infra repository (agent-rack-policies). 15-agent-rack.sh redeploys these
# from the live infra checkout on the new machine; the share copy is the
# fallback when no infra checkout exists yet. runtime/ holds per-machine SSE
# auth tokens and session state and must not be restored.
AGENT_RACK_TARGET="$HOME/.config/agent-rack"; AGENT_RACK_ITEMS=(config.json agent-rack.profiles.json agent-rack.security-overlay.json DELEGATION.md WORKER-CONTRACT.txt MODEL-CATALOG.json RESEARCH.md SOURCES.md ROOT-BLOCK.md agent-rack-join-patch.mjs)

# Files that must be private (chmod 600 after a pull)
SENSITIVE_BASENAMES="auth.json opencode.jsonc settings.json config.toml claude_desktop_config.json config.json"

MOUNTED=false

# ─────────────────────────────────────────────────────────────────────────────
# Credentials, stale-share unmount, mount and cleanup come from the shared
# SMB helpers in core/functions.sh (same mechanism as 04-ssh-keys.sh).
# ─────────────────────────────────────────────────────────────────────────────
trap smb_cleanup EXIT INT TERM HUP

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
backup_target() { # $1 = path to back up if it exists
  local p="$1"
  if [[ -e "$p" ]]; then
    local b="${p}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -R "$p" "$b"
    print_info "Backed up $(basename "$p") -> $(basename "$b")"
  fi
}

copy_item() { # $1 = src (file/dir), $2 = dst (full path incl. name)
  if [[ -d "$1" ]]; then
    rm -rf "$2"
    cp -R "$1" "$2"
  else
    cp "$1" "$2"
  fi
}

is_sensitive() { # $1 = basename
  case " $SENSITIVE_BASENAMES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Sync one tool. $1 = share subdir, $2 = local target dir, $3.. = items
sync_tool() {
  local sub="$1" target="$2"; shift 2
  local items=("$@")
  local share_dir="${MOUNT_POINT}/${sub}"
  local count=0

  if [[ "$MODE" == "pull" ]]; then
    if [[ ! -d "$share_dir" ]]; then
      print_info "No '${sub}' folder on the share — skipping."
      return 0
    fi
    ensure_directory "$target" false
    for item in "${items[@]}"; do
      local src="${share_dir}/${item}" dst="${target}/${item}"
      [[ -e "$src" ]] || continue
      backup_target "$dst"
      copy_item "$src" "$dst"
      if [[ -f "$dst" ]] && is_sensitive "$item"; then chmod 600 "$dst"; fi
      print_success "pulled ${sub}/${item}"
      ((count++))
    done
    print_info "${sub}: ${count} item(s) copied into ${target}"
  else # save
    ensure_directory "$share_dir" false
    for item in "${items[@]}"; do
      local src="${target}/${item}" dst="${share_dir}/${item}"
      [[ -e "$src" ]] || continue
      copy_item "$src" "$dst"
      print_success "saved ${sub}/${item} -> share"
      ((count++))
    done
    print_info "${sub}: ${count} item(s) uploaded to the share"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Confirm destructive-ish save
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "save" ]]; then
  print_info "SAVE mode: your local AI configs will be uploaded to ${SMB_SERVER}/${SMB_AI_PATH}"
  ask_for_confirmation "Upload current local Claude/Codex/OpenCode/agent-rack configs to the share?"
  answer_is_yes || { print_info "Aborted."; exit 0; }
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mount the share (Finder uses Keychain credentials) — same flow as ssh-keys
# ─────────────────────────────────────────────────────────────────────────────
get_smb_credentials || exit 1
unmount_stale_share
mount_smb_share "${SMB_AI_PATH}"

# ─────────────────────────────────────────────────────────────────────────────
# Sync all three tools
# ─────────────────────────────────────────────────────────────────────────────
print_info "AI config sync — mode: ${MODE}"
sync_tool "claude"   "$CLAUDE_TARGET"   "${CLAUDE_ITEMS[@]}"
sync_tool "claude-desktop" "$CLAUDE_DESKTOP_TARGET" "${CLAUDE_DESKTOP_ITEMS[@]}"
sync_tool "codex"    "$CODEX_TARGET"    "${CODEX_ITEMS[@]}"
sync_tool "opencode" "$OPENCODE_TARGET" "${OPENCODE_ITEMS[@]}"
sync_tool "agent-rack" "$AGENT_RACK_TARGET" "${AGENT_RACK_ITEMS[@]}"

if [[ "$MODE" == "pull" ]]; then
  # OpenCode custom tools/plugins import @opencode-ai/plugin — node_modules is
  # deliberately NOT synced, so install deps from the pulled package.json.
  # Without this, the tools fail to load on a fresh machine (silent: the app
  # answers nothing). Requires npm (Brewfile installs node before this step).
  if [[ -f "$OPENCODE_TARGET/package.json" ]] && command_exists npm; then
    print_info "Installing OpenCode tool/plugin deps (npm install in $OPENCODE_TARGET)…"
    ( cd "$OPENCODE_TARGET" && npm install --no-fund --no-audit >/dev/null 2>&1 ) \
      && print_success "OpenCode deps installed" \
      || print_error "npm install failed in $OPENCODE_TARGET — run it manually so custom tools load"
  fi
  print_success "AI configs pulled from the tresor."
  print_info "If a tool still asks you to log in, run its login once (e.g. 'claude', 'codex login')."
  print_info "OpenCode/Lumo: opencode.jsonc from the share already contains your apiKey."
  print_info "agent-rack: run utils/15-agent-rack.sh after the pull so version, registrations, and skills are (re)installed."
  print_info "After pull: fully quit + reopen the OpenCode app so it reloads config/tools."
else
  print_success "AI configs saved to the tresor. Nothing was written to this git repo."
fi
