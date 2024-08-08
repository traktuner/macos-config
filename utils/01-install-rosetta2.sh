#!/usr/bin/env bash

echo "=> Rosetta 2"

arch=$(uname -p)
if [[ "$arch" = 'arm' ]]; then
    echo "Installing Rosetta 2"
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    exit 0
else
    echo "Rosetta not needed on your system."
    exit 0
fi