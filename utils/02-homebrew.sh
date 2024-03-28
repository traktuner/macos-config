#!/usr/bin/env bash

echo "=> Homebrew"

arch=$(get_arch)

if [[ ! -f $(which brew) ]]
then
  print_info "Installing..."

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  /opt/homebrew/bin/brew bundle --file="$ROOT_DIR/core/Brewfile" --retry=3
  /opt/homebrew/bin/brew cleanup && \
  /opt/homebrew/bin/brew upgrade && \
  /opt/homebrew/bin/brew upgrade --cask && \
  /opt/homebrew/bin/brew update && \
  /opt/homebrew/bin/brew doctor

  print_success "Completed..."
else
  print_success "Skipping..."
fi
