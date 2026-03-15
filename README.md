# macOS Config

Automated configuration for new macOS installations. Tested on macOS Sonoma (14), Sequoia (15) and Tahoe (26).

## Features

- **Modular Scripts**: Each aspect of configuration is split into separate scripts
- **Interactive Selection**: Choose which scripts to run (single, range, or list)
- **Robust Error Handling**: Retry mechanisms, logging, and comprehensive validation
- **Security**: Time Machine snapshots, secure credential handling, cleanup traps
- **Internet Check**: Verifies connectivity before starting
- **Full Disk Access**: Automatic detection and guidance when needed

## Prerequisites

- macOS 14.0 (Sonoma) or higher
- Internet connection
- Apple ID signed in (for Mac App Store apps)
- SMB access for SSH keys (optional)

## Installation

```bash
git clone <your-repo-url>
cd macos-config
chmod +x bootstrap
./bootstrap
```

## Project Structure

```
macos-config/
├── bootstrap                 # Main script with interactive menu
├── core/
│   ├── Brewfile              # Homebrew packages, casks, and MAS apps
│   └── functions.sh          # Shared utility functions
├── utils/
│   ├── 00-preflight.sh       # Time Machine snapshot, CrashPlan, toggleAirport
│   ├── 01-install-rosetta2.sh  # Rosetta 2 for Apple Silicon
│   ├── 02-homebrew.sh        # Homebrew installation & packages
│   ├── 03-macos.sh           # macOS system preferences (defaults write)
│   ├── 04-ssh-keys.sh        # SSH keys from SMB share
│   ├── 05-config-profile.sh  # Install configuration profile from iCloud
│   ├── 06-macos-update.sh    # macOS software updates
│   └── deploy.properties     # CrashPlan deployment config
└── renovate.json             # Automated dependency updates
```

## Usage

1. **Full Installation**: Choose option `0` to run all scripts in order
2. **Selective Installation**: Choose individual scripts by number
3. **Range/List Selection**: Use ranges like `1-3` or lists like `1,3,5`

## Configuration

### Homebrew packages
Edit `core/Brewfile` to add/remove apps. Custom casks are in the `traktuner/traktuner` tap.

### macOS settings
Modify `utils/03-macos.sh` for personal preferences. Settings are organized by category (UI/UX, Finder, Dock, Safari, etc.).

### SSH Keys
Configure the SMB server/share in `utils/04-ssh-keys.sh`.

## Security

- Time Machine snapshot before making changes
- SMB credentials cleaned up via trap on exit
- SSH key permissions automatically set (600/644)
- No passwords exposed in process list
- Full Disk Access verified before modifying protected settings

## Logs

All output is logged to `/tmp/macos-config.log` with timestamps.

## Maintenance

Dependency updates are automated via Renovate (weekly, Monday mornings).

```bash
# Manual Homebrew maintenance
brew update && brew upgrade && brew cleanup
```

## Notes on macOS Tahoe (26)

- `com.apple.screensaver askForPassword` is deprecated - use Lock Screen settings or MDM profiles
- `com.apple.SoftwareUpdate ScheduleFrequency` has no effect since Catalina
- Safari defaults require Full Disk Access for Terminal
- Window tiling margins can be controlled via `com.apple.WindowManager`
- macOS Tahoe is the last version supporting Intel Macs
