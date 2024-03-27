#!/usr/bin/env bash

echo "=> Config files"

config_content="
Host udmp
	HostName 192.168.0.1
	HostkeyAlgorithms +ssh-rsa
	PubkeyAcceptedAlgorithms +ssh-rsa

Host github.com
	Hostname ssh.github.com
	Port 443
"
add_config ".ssh" "$HOME" "$config_content"

# .bash_profile
config_content="
# .bash_profile
# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
"
add_config ".bash_profile" "$HOME" "$config_content"

# .bashrc
config_content="
# .bashrc
# User specific aliases and functions
. .alias
alias python='python3'
alias ll='ls -la'

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi
"
add_config ".bashrc" "$HOME" "$config_content"

print_success "Completed..."