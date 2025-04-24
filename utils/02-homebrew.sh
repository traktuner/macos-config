#!/usr/bin/env bash
set -euo pipefail

# Load shared functions from core
source "$ROOT_DIR/core/functions.sh"

print_info "Homebrew setup"

# Keep sudo timestamp alive for any CLI sudo calls
ask_for_sudo

# -------------------------------------------------------------------
# Install Casks into ~/Applications to avoid repeated sudo prompts
# -------------------------------------------------------------------
USER_APPDIR="$HOME/Applications"
print_info "Ensuring user Applications directory exists at $USER_APPDIR"
mkdir -p "$USER_APPDIR"
export HOMEBREW_CASK_OPTS="--appdir=$USER_APPDIR"
print_success "Casks will install into $USER_APPDIR"

# -------------------------------------------------------------------
# retry function: retry <max-tries> <delay-seconds> <command...>
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
      print_error "Attempt $attempt/$max_tries for '$*' failed. Retrying in $delay_secs seconds..."
      sleep "$delay_secs"
      (( attempt++ ))
    fi
  done

  print_success "Command '$*' succeeded on attempt $attempt."
}

# -------------------------------------------------------------------
# 1) Install Homebrew if it's not already present
#    Log installer output to a temp file to keep the console clean
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
  print_success "Homebrew is already installed."
fi

# -------------------------------------------------------------------
# 2) Initialize Homebrew in the current shell and persist to zsh
# -------------------------------------------------------------------
# 2a) For this script
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2b) For all future zsh sessions
BREW_ENV_CMD='eval "$(/opt/homebrew/bin/brew shellenv)"'
for PROFILE in "$HOME/.zprofile" "$HOME/.zshrc"; do
  [[ -f $PROFILE ]] || touch "$PROFILE"
  if ! grep -Fxq "$BREW_ENV_CMD" "$PROFILE"; then
    print_info "Appending Homebrew environment setup to $PROFILE"
    printf '\n# Load Homebrew environment\n%s\n' "$BREW_ENV_CMD" >>"$PROFILE"
    print_success "Appended brew shellenv to $PROFILE"
  else
    print_success "Homebrew environment already present in $PROFILE"
  fi
done

# -------------------------------------------------------------------
# 3) Prefetch all formulae and casks into Homebrew’s cache
#    so we can install everything offline in the next step
# -------------------------------------------------------------------
print_info "Prefetching formulae and casks from Brewfile…"
# extract lists
formulae=($(brew bundle list --file="$ROOT_DIR/core/Brewfile" --formula))
casks=($(brew bundle list --file="$ROOT_DIR/core/Brewfile" --cask))

# fetch each formula
for f in "${formulae[@]}"; do
  print_info "Fetching formula: $f"
  retry 3 5 brew fetch "$f" || { print_error "Failed to fetch $f"; exit 1; }
done

# fetch each cask
for c in "${casks[@]}"; do
  print_info "Fetching cask: $c"
  retry 3 5 brew fetch --cask "$c" || { print_error "Failed to fetch cask $c"; exit 1; }
done

print_success "Prefetch complete."

# -------------------------------------------------------------------
# 4) Run brew bundle to install all entries in your Brewfile
# -------------------------------------------------------------------
print_info "Running brew bundle…"
retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1

# -------------------------------------------------------------------
# 5) Cleanup, upgrade, and update Homebrew itself, formulae & casks
# -------------------------------------------------------------------
print_info "Cleaning up old downloads and cache…"
retry 2 5 brew cleanup

print_info "Upgrading installed formulae and casks…"
retry 2 5 brew upgrade

print_info "Updating Homebrew itself…"
retry 2 5 brew update

# -------------------------------------------------------------------
# 6) Final health check
# -------------------------------------------------------------------
if brew doctor; then
  print_success "brew doctor: All good!"
else
  print_error "brew doctor found issues."
fi
