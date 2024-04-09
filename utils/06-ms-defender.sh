#!/usr/bin/env bash

echo "=> Microsoft Defender"

if [[ -f $(which brew) ]]
then
  curl -L "https://gist.githubusercontent.com/traktuner/5f94a1b003eede9a415a8358a8e61f09/raw/1279bb0f5e738b46b8a910d5298f699992ca06a4/microsoft-defender.rb" --output "$(pwd)/microsoft-defender.rb"
  /opt/homebrew/bin/brew install --cask "$(pwd)/microsoft-defender.rb"
  rm -rf "$(pwd)/microsoft-defender.rb"
  echo "Completed..."
else
  echo "Skipping..."
fi