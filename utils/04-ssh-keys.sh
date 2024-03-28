#!/usr/bin/env bash

echo "=> SSH Keyfiles"

smb_path="172.16.10.100/tresor/ssh"
mount_path="/Volumes/ssh"
target_folder="$HOME/.ssh"

read -p "Please enter your smb username: " smb_user
read -s -p "Please enter your smb password: " smb_password

open "smb://$smb_user:$smb_password@$smb_path"
open_result=$?
sleep 10

ls -la $mount_path

if [ $open_result -eq 0 ]; then
    # Copy files from the mounted volume
    cp "$mount_path"/* "$target_folder"
    
    # Unmount the volume
    diskutil unmount "$mount_path"
    unmount_result=$?
    
    if [ $unmount_result -eq 0 ]; then
        echo "Unmounted successfully."
    else
        echo "Unmounting failed."
    fi
else
    echo "SMB mount failed..."
fi

# Delete password
unset smb_password