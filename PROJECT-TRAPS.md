# Project traps

- **Do not treat reinstalling Xcode as a complete developer backup.** Xcode archives, provisioning profiles, and signing certificates are separate from the Xcode app. Back up Archives and profiles, and export certificates as `.p12` files before erasing the Mac. See `utils/06-backup-before-reinstall.sh`.
- **Do not install UrBackup through `utils/07-manual-apps.sh`.** The `urbackup-client` cask in `core/Brewfile` installs the current macOS package from the trusted tap. The manual script must remain a no-op unless a future app is genuinely unavailable through Homebrew.
- **Do not assume Logic or audio plugin presets live only under `~/Library/Audio`.** On this Mac, Logic content is under `/Library/Application Support/Logic`, Nexus content is under `/Library/Audio/Presets`, and Sylenth1 soundbanks and its data folder are under `~/Library/Application Support/LennarDigital/Sylenth1`; back up all three locations before reinstalling macOS (`utils/06-backup-before-reinstall.sh`).
- **Do not commit a user-specific backup destination.** Keep the script portable with `$HOME`, an argument, or `BACKUP_DESTINATION`.
