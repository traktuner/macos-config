#!/usr/bin/env bash

echo "=> Homebrew"

arch=$(uname -m)

if [[ ! -f $(which brew) ]]
then
  print_info "Installing..."

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ $arch == "arm64" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  brew bundle --file="$ROOT_DIR/core/Brewfile"
  brew cleanup && brew upgrade && brew update && brew doctor

  print_success "Completed..."
else
  print_success "Skipping..."
fi
