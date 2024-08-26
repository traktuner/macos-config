#!/usr/bin/env bash

echo "=> Homebrew"

if [[ ! -f $(which brew) ]]
then
  print_info "Installing..."

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  /opt/homebrew/bin/brew bundle --file="$ROOT_DIR/core/Brewfile"
  /opt/homebrew/bin/brew cleanup && \
  /opt/homebrew/bin/brew upgrade && \
  /opt/homebrew/bin/brew update && \
  /opt/homebrew/bin/brew doctor
  eval $(/opt/homebrew/bin/brew shellenv)

  print_success "Completed..."
else
  print_success "Skipping..."
fi
