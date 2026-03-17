#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Configuring zsh shell environment"

ZSHRC="$HOME/.zshrc"
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

###############################################################################
# Build .zshrc with completions, syntax highlighting, autosuggestions, starship
###############################################################################

# Backup existing .zshrc if present
if [[ -f "$ZSHRC" ]]; then
  cp "$ZSHRC" "${ZSHRC}.backup.$(date +%Y%m%d_%H%M%S)"
  print_info "Backed up existing .zshrc"
fi

cat > "$ZSHRC" <<EOF
# -- Completions (must come before compinit)
FPATH=${BREW_PREFIX}/share/zsh-completions:\$FPATH
autoload -Uz compinit
compinit

# -- Syntax Highlighting & Autosuggestions (skip in Warp — has these built-in)
if [[ "\$TERM_PROGRAM" != "WarpTerminal" ]]; then
  [[ -f ${BREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \\
    source ${BREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  [[ -f ${BREW_PREFIX}/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \\
    source ${BREW_PREFIX}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi

# -- Starship prompt
eval "\$(starship init zsh)"
EOF

print_success ".zshrc configured"

###############################################################################
# Starship minimal config (if not already present)
###############################################################################
STARSHIP_CONFIG="$HOME/.config/starship.toml"
if [[ ! -f "$STARSHIP_CONFIG" ]]; then
  ensure_directory "$HOME/.config" false
  cat > "$STARSHIP_CONFIG" <<'TOML'
# Minimal starship config — show what matters, hide the rest
format = """$directory$git_branch$git_status$cmd_duration$line_break$character"""

[directory]
truncation_length = 3

[git_branch]
format = "[$branch]($style) "
style = "bold purple"

[git_status]
format = '([$all_status$ahead_behind]($style) )'

[cmd_duration]
min_time = 2000
format = "[$duration]($style) "

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"
TOML
  print_success "Starship config created"
else
  print_info "Starship config already exists — skipping"
fi

###############################################################################
# Rebuild completion cache
###############################################################################
rm -f "$HOME/.zcompdump"
print_success "Completion cache cleared (will rebuild on next shell start)"

print_success "Shell configuration complete"
print_info "Open a new terminal window to see changes."
