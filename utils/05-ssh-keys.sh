#!/usr/bin/env bash

echo "=> SSH Keyfiles"

smb_path="172.16.10.100/tresor/ssh"
mount_path="/Volumes/ssh"
target_folder="$HOME/.ssh"

if [ ! -d "$target_folder" ]; then
    echo "Create target folder..."
    mkdir -p "$target_folder"
fi

read -p "Please enter your smb username: " smb_user
read -s -p "Please enter your smb password: " smb_password

open "smb://$smb_user:$smb_password@$smb_path"
open_result=$?
sleep 10

ls -la /Volumes/ssh

if [ $open_result -eq 0 ]; then
    cp $mount_path/* $target_folder
    print_success "Completed..."
else
    print_error "smb mount failed..."
fi

# Delete password
unset smb_password