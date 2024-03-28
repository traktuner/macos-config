#!/usr/bin/env zsh

echo "=> Config files"

config_content="
Host udmp
	HostName 192.168.0.1
	HostkeyAlgorithms +ssh-rsa
	PubkeyAcceptedAlgorithms +ssh-rsa

Host anakin
	HostName 172.16.10.100

Host github.com
	Hostname ssh.github.com
	Port 443
"
add_config ".ssh" "$HOME" "$config_content"

# .zshenv
config_content="
# .zshenv
# Get the aliases and functions
if [ -f ~/.zshrc ]; then
    . ~/.zshrc
fi
"
add_config ".zshenv" "$HOME" "$config_content"

# .zshrc
config_content="
# .zshrc
# User specific aliases and functions
. .alias
alias python='python3'
alias ll='ls -la'
eval $(/opt/homebrew/bin/brew shellenv)

# Source global definitions
if [ -f /etc/zshrc ]; then
    . /etc/zshrc
fi
"
add_config ".zshrc" "$HOME" "$config_content"

print_success "Completed..."