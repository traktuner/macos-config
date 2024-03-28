#!/usr/bin/env zsh

echo "=> Homebrew"

arch=$(get_arch)

if [[ ! -f $(which brew) ]]
then
  print_info "Installing..."

  /bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew bundle --file="$ROOT_DIR/core/Brewfile"
  brew cleanup && brew upgrade && brew update && brew doctor

  print_success "Completed..."
else
  print_success "Skipping..."
fi
