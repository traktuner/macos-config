#!/usr/bin/env bash
set -euo pipefail

# Works both from bootstrap (ROOT_DIR exported) and standalone (e.g. `bash utils/12-ai-config.sh save`)
: "${ROOT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Load shared functions
source "$ROOT_DIR/core/functions.sh"

# Preserve the per-run Infra source through config.properties and child scripts.
INFRA_HARNESS_SOURCE_OVERRIDE="${INFRA_HARNESS_SOURCE:-}"

# Load configuration
CONFIG_FILE="$ROOT_DIR/utils/config.properties"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  print_info "Configuration loaded from config.properties"
else
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

if [[ -n "$INFRA_HARNESS_SOURCE_OVERRIDE" ]]; then
  export INFRA_HARNESS_SOURCE="$INFRA_HARNESS_SOURCE_OVERRIDE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Owner-private AI state for Claude, Codex, and OpenCode lives on the SMB
# tresor. Infra owns all shared harness policy, skills, plugins, and profiles.
#
#   Mode:  pull  (default) copy configs FROM the share INTO your machine
#          save            copy your current local configs UP to the share
#          Run from the bootstrap menu = pull. To seed/update the share:
#            bash utils/12-ai-config.sh save
#
# Expected owner-private layout on the share (SMB_AI_PATH):
#   <share>/claude/     -> ~/.claude/              (settings.json)
#   <share>/claude-desktop/ -> ~/Library/Application Support/Claude/
#   <share>/codex/      -> ~/.codex/               (config.toml, hooks.json, auth.json)
#   <share>/opencode/   -> ~/.config/opencode/     (opencode.jsonc)
# Infra owns rules, skills, plugins, agent-rack configuration, profiles, code,
# and lockfiles. This script never restores or saves them.
# ─────────────────────────────────────────────────────────────────────────────

MODE="${1:-pull}"
if [[ "$MODE" != "pull" && "$MODE" != "save" ]]; then
  print_error "Unknown mode '$MODE'. Use: pull (default) or save."
  exit 1
fi

# Check the authoritative package before this script mounts the share or
# modifies owner-local state. The check mode performs no installation.
if [[ "$MODE" == "pull" ]]; then
  bash "$ROOT_DIR/utils/15-agent-rack.sh" --check-source
fi

# Configuration (overridable via config.properties)
SMB_SERVER="${SMB_SERVER:-172.16.10.200}"
SMB_AI_PATH="${SMB_AI_PATH:-tom/tresor/ai-config}"
MOUNT_POINT="${SMB_AI_MOUNT_POINT:-/Volumes/ai-config}"
SMB_TIMEOUT="${SMB_TIMEOUT:-30}"

# Curated owner-private state only. These files can contain credentials and
# keep private permissions after a pull. Do not add managed Infra state here.
CLAUDE_TARGET="$HOME/.claude";           CLAUDE_ITEMS=(settings.json)
CLAUDE_DESKTOP_TARGET="$HOME/Library/Application Support/Claude"; CLAUDE_DESKTOP_ITEMS=(claude_desktop_config.json)
CODEX_TARGET="$HOME/.codex";             CODEX_ITEMS=(config.toml hooks.json auth.json)
OPENCODE_TARGET="$HOME/.config/opencode"; OPENCODE_ITEMS=(opencode.jsonc)

# Files that must be private (chmod 600 after a pull)
SENSITIVE_BASENAMES="auth.json opencode.jsonc settings.json config.toml claude_desktop_config.json config.json"

MOUNTED=false

# ─────────────────────────────────────────────────────────────────────────────
# Credentials, stale-share unmount, mount and cleanup come from the shared
# SMB helpers in core/functions.sh (same mechanism as 04-ssh-keys.sh).
# ─────────────────────────────────────────────────────────────────────────────
trap 'finish_private_pull $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
backup_target() { # $1 = path to back up if it exists
  local p="$1"
  if [[ -e "$p" ]]; then
    local b="${p}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -R "$p" "$b" || return 1
    print_info "Backed up $(basename "$p") -> $(basename "$b")"
  fi
}

copy_item() { # $1 = src (file/dir), $2 = dst (full path incl. name)
  if [[ -d "$1" ]]; then
    mkdir -p "$2" || return 1
    # The whole curated item is backed up before synchronization. Remove
    # obsolete entries so a later restore cannot resurrect retired code.
    rsync -a --delete "$1/" "$2/" || return 1
  else
    mkdir -p "$(dirname "$2")" || return 1
    cp "$1" "$2" || return 1
  fi
}

needs_sync() { # $1 = src, $2 = dst
  if [[ -d "$1" ]]; then
    [[ ! -d "$2" ]] && return 0
    local changes
    changes="$(rsync -anir --delete "$1/" "$2/")" || return 0
    [[ -n "$changes" ]]
    return
  fi
  [[ ! -f "$2" ]] || ! cmp -s "$1" "$2"
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
    ensure_directory "$target" false || return 1
    for item in "${items[@]}"; do
      local src="${share_dir}/${item}" dst="${target}/${item}"
      [[ -e "$src" ]] || continue
      [[ ! -L "$src" && ! -L "$dst" ]] || { print_error "Refusing symbolic-link private item: ${sub}/${item}"; return 1; }
      if ! needs_sync "$src" "$dst"; then
        if [[ -f "$dst" ]] && is_sensitive "$item"; then chmod 600 "$dst" || return 1; fi
        print_info "${sub}/${item} already current"
        continue
      fi
      backup_target "$dst" || return 1
      copy_item "$src" "$dst" || return 1
      if [[ -f "$dst" ]] && is_sensitive "$item"; then chmod 600 "$dst" || return 1; fi
      print_success "pulled ${sub}/${item}"
      count=$((count + 1))
    done
    print_info "${sub}: ${count} item(s) copied into ${target}"
  else # save
    ensure_directory "$share_dir" false || return 1
    for item in "${items[@]}"; do
      local src="${target}/${item}" dst="${share_dir}/${item}"
      [[ -e "$src" ]] || continue
      if ! needs_sync "$src" "$dst"; then
        print_info "${sub}/${item} already current on share"
        continue
      fi
      backup_target "$dst" || return 1
      copy_item "$src" "$dst" || return 1
      print_success "saved ${sub}/${item} -> share"
      count=$((count + 1))
    done
    print_info "${sub}: ${count} item(s) uploaded to the share"
  fi
}

# The private pull has six independently curated files. Keep an owner-only
# snapshot until the shared harness reconciliation succeeds, so a failed final
# apply cannot leave this set half restored. Existing backup_target snapshots
# remain user recovery copies; this directory exists only for this transaction.
PRIVATE_PULL_ROLLBACK=""
snapshot_private_pull() {
  PRIVATE_PULL_ROLLBACK="$(mktemp -d "${TMPDIR:-/tmp}/ai-config-pull.XXXXXX")" || return 1
  chmod 700 "$PRIVATE_PULL_ROLLBACK" || return 1
  local index=0 target item path
  for target in "$CLAUDE_TARGET" "$CLAUDE_DESKTOP_TARGET" "$CODEX_TARGET" "$OPENCODE_TARGET"; do
    local -a entries=()
    case "$target" in
      "$CLAUDE_TARGET") entries=("${CLAUDE_ITEMS[@]}") ;;
      "$CLAUDE_DESKTOP_TARGET") entries=("${CLAUDE_DESKTOP_ITEMS[@]}") ;;
      "$CODEX_TARGET") entries=("${CODEX_ITEMS[@]}") ;;
      "$OPENCODE_TARGET") entries=("${OPENCODE_ITEMS[@]}") ;;
    esac
    for item in "${entries[@]}"; do
      path="$target/$item"
      local ancestor="$target"
      while [[ "$ancestor" != / ]]; do
        [[ ! -L "$ancestor" ]] || { print_error "Refusing symbolic-link private parent: $ancestor"; return 1; }
        ancestor="$(dirname "$ancestor")"
      done
      printf '%s\n' "$path" >> "$PRIVATE_PULL_ROLLBACK/paths"
      if [[ -L "$path" ]]; then print_error "Refusing symbolic-link private target: $path"; return 1; fi
      if [[ -e "$path" ]]; then
        [[ -f "$path" ]] || { print_error "Refusing non-file private target: $path"; return 1; }
        printf 'present\n' > "$PRIVATE_PULL_ROLLBACK/$index.state"
        cp -p "$path" "$PRIVATE_PULL_ROLLBACK/$index.file" || return 1
      else
        printf 'absent\n' > "$PRIVATE_PULL_ROLLBACK/$index.state"
      fi
      index=$((index + 1))
    done
  done
}

rollback_private_pull() {
  [[ -n "$PRIVATE_PULL_ROLLBACK" && -d "$PRIVATE_PULL_ROLLBACK" ]] || return 0
  local index=0 path state
  while IFS= read -r path; do
    state="$(<"$PRIVATE_PULL_ROLLBACK/$index.state")"
    [[ ! -L "$path" ]] || { print_error "Cannot roll back symbolic-link private target: $path"; return 1; }
    if [[ "$state" == present ]]; then
      mkdir -p "$(dirname "$path")"
      cp -p "$PRIVATE_PULL_ROLLBACK/$index.file" "$path" || return 1
    else
      rm -f "$path"
    fi
    index=$((index + 1))
  done < "$PRIVATE_PULL_ROLLBACK/paths"
  rm -rf "$PRIVATE_PULL_ROLLBACK"
  PRIVATE_PULL_ROLLBACK=""
}

commit_private_pull() {
  [[ -z "$PRIVATE_PULL_ROLLBACK" ]] || rm -rf "$PRIVATE_PULL_ROLLBACK"
  PRIVATE_PULL_ROLLBACK=""
}

finish_private_pull() {
  local status="$1"
  trap - EXIT
  if [[ -n "$PRIVATE_PULL_ROLLBACK" ]]; then
    if ! rollback_private_pull; then
      print_error "Private restore rollback failed; retain snapshot: $PRIVATE_PULL_ROLLBACK"
      status=1
    fi
  fi
  smb_cleanup
  exit "$status"
}

# ─────────────────────────────────────────────────────────────────────────────
# Confirm destructive-ish save
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "save" ]]; then
  print_info "SAVE mode: your local AI configs will be uploaded to ${SMB_SERVER}/${SMB_AI_PATH}"
  ask_for_confirmation "Upload current owner-private Claude, Codex, and OpenCode state to the share?"
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
if [[ "$MODE" == pull ]] && ! snapshot_private_pull; then
  commit_private_pull
  exit 1
fi
if ! sync_tool "claude" "$CLAUDE_TARGET" "${CLAUDE_ITEMS[@]}" ||
   ! sync_tool "claude-desktop" "$CLAUDE_DESKTOP_TARGET" "${CLAUDE_DESKTOP_ITEMS[@]}" ||
   ! sync_tool "codex" "$CODEX_TARGET" "${CODEX_ITEMS[@]}" ||
   ! sync_tool "opencode" "$OPENCODE_TARGET" "${OPENCODE_ITEMS[@]}"; then
  rollback_private_pull
  exit 1
fi

if [[ "$MODE" == "pull" ]]; then
  if ! bash "$ROOT_DIR/utils/15-agent-rack.sh"; then
    rollback_private_pull
    print_error "Infra harness reconciliation failed; restored owner-private AI state."
    exit 1
  fi
  commit_private_pull
  print_success "AI configs pulled from the tresor."
  print_info "If a tool still asks you to log in, run its login once (e.g. 'claude', 'codex login')."
  print_info "OpenCode/Lumo: opencode.jsonc from the share already contains your apiKey."
  print_info "Infra harness reconciliation completed after the private-state pull."
  print_info "After pull: fully quit + reopen the OpenCode app so it reloads config/tools."
else
  print_success "AI configs saved to the tresor. Nothing was written to this git repo."
fi
