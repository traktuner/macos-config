#!/usr/bin/env bash
set -euo pipefail

# Load shared functions from core
source "$ROOT_DIR/core/functions.sh"

print_info "Homebrew setup"

# Keep sudo timestamp alive
ask_for_sudo

# -------------------------------------------------------------------
# 0) Prepare for user‐only Cask installs (avoids repeated sudo)
# -------------------------------------------------------------------
USER_APPDIR="$HOME/Applications"
print_info "Ensuring user Applications directory exists at $USER_APPDIR"
mkdir -p "$USER_APPDIR"
export HOMEBREW_CASK_OPTS="--appdir=$USER_APPDIR"
print_success "Casks will install into $USER_APPDIR"

# -------------------------------------------------------------------
# retry function (max_tries, delay, command…)
# -------------------------------------------------------------------
retry() {
  local -r -i max_tries="${1:-3}"
  local -r -i delay_secs="${2:-5}"
  shift 2
  local -i attempt=1
  until "$@"; do
    if (( attempt >= max_tries )); then
      print_error "Command '$*' failed after $attempt attempts."
      return 1
    else
      print_error "Attempt $attempt/$max_tries for '$*' failed. Retrying in $delay_secss seconds..."
      sleep "$delay_secs"
      (( attempt++ ))
    fi
  done
  print_success "Command '$*' succeeded on attempt $attempt."
}

# -------------------------------------------------------------------
# 1) Install Homebrew if missing (log to keep console clean)
# -------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
  HOMEBREW_LOG="/tmp/homebrew-install.log"
  print_info "Installing Homebrew… (logging to $HOMEBREW_LOG)"
  if retry 3 10 env NONINTERACTIVE=1 /bin/bash -c \
       "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
       >"$HOMEBREW_LOG" 2>&1; then
    print_success "Homebrew installed successfully."
  else
    print_error "Homebrew installation failed. See $HOMEBREW_LOG for details."
    exit 1
  fi
else
  print_success "Homebrew already installed."
fi

# -------------------------------------------------------------------
# 2) Initialize Homebrew for this script and future shells
# -------------------------------------------------------------------
eval "$(/opt/homebrew/bin/brew shellenv)"

BREW_ENV_CMD='eval "$(/opt/homebrew/bin/brew shellenv)"'
for PROFILE in "$HOME/.zprofile" "$HOME/.zshrc"; do
  [[ -f $PROFILE ]] || touch "$PROFILE"
  if ! grep -Fxq "$BREW_ENV_CMD" "$PROFILE"; then
    print_info "Appending Homebrew setup to $PROFILE"
    printf '\n# Load Homebrew environment\n%s\n' "$BREW_ENV_CMD" >>"$PROFILE"
    print_success "Appended brew shellenv to $PROFILE"
  else
    print_success "Homebrew env already in $PROFILE"
  fi
done

# -------------------------------------------------------------------
# 3) Tap all GitHub taps from your Brewfile (must precede fetch/install)
# -------------------------------------------------------------------
print_info "Tapping all repositories from Brewfile…"
taps=( $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --tap) )
for t in "${taps[@]}"; do
  print_info "Tapping $t"
  retry 3 5 brew tap "$t" || { print_error "Failed to tap $t"; exit 1; }
done
print_success "All taps OK"

# -------------------------------------------------------------------
# 4) Prefetch formulae and casks into Homebrew cache
# -------------------------------------------------------------------
print_info "Prefetching formulae and casks…"
formulae=( $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --formula) )
casks=(   $(brew bundle list --file="$ROOT_DIR/core/Brewfile" --cask)   )

for f in "${formulae[@]}"; do
  print_info "Fetching formula: $f"
  retry 3 5 brew fetch "$f" || { print_error "Failed to fetch $f"; exit 1; }
done

for c in "${casks[@]}"; do
  print_info "Fetching cask: $c"
  retry 3 5 brew fetch --cask "$c" || { print_error "Failed to fetch cask $c"; exit 1; }
done
print_success "Prefetch complete"

# -------------------------------------------------------------------
# 5) Run brew bundle to install everything from your Brewfile
# -------------------------------------------------------------------
print_info "Running brew bundle…"
retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1

# -------------------------------------------------------------------
# 6) Cleanup, upgrade & update
# -------------------------------------------------------------------
print_info "Cleaning up…"
retry 2 5 brew cleanup

print_info "Upgrading…"
retry 2 5 brew upgrade

print_info "Updating…"
retry 2 5 brew update

# -------------------------------------------------------------------
# 7) Final health check
# -------------------------------------------------------------------
if brew doctor; then
  print_success "brew doctor: All good!"
else
  print_error "brew doctor found issues"
fi
