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
│   ├── 00-preflight.sh          # Time Machine snapshot, CrashPlan, toggleAirport
│   ├── 01-install-rosetta2.sh   # Rosetta 2 for Apple Silicon
│   ├── 02-homebrew.sh           # Homebrew installation & packages
│   ├── 03-macos.sh              # macOS system preferences (defaults write)
│   ├── 04-ssh-keys.sh           # SSH keys from SMB share
│   ├── 05-config-profile.sh     # Install configuration profile from iCloud
│   ├── 06-backup-before-reinstall.sh # Backup and restore local Mac state
│   ├── 07-manual-apps.sh        # Apps not available via Homebrew (.pkg/.dmg)
│   ├── 08-default-apps.sh       # Default mail app & browser
│   ├── 09-dock-layout.sh        # Dock layout via dockutil
│   ├── 10-shell-config.sh       # zsh + starship configuration
│   ├── 11-firefox-extensions.sh # Firefox policies.json (extensions & prefs)
│   ├── 12-ai-config.sh          # Restore/save private AI harness configuration
│   ├── 13-onyx-mcp.sh           # Configure authenticated Onyx MCP locally
│   ├── 14-xcode-worker.sh       # T3-reachable, restricted XcodeBuildMCP worker
│   ├── 15-agent-rack.sh         # Pinned stock agent-rack MCP for local AI harnesses
│   ├── config.properties        # General configuration (SMB, wallpaper, etc.)
│   └── deploy.properties        # CrashPlan deployment config (copied to CrashPlan)
└── renovate.json             # Automated dependency updates
```

## Usage

1. **Full Installation**: Choose option `0` to run all scripts in order
2. **Selective Installation**: Choose individual scripts by number
3. **Range/List Selection**: Use ranges like `1-3` or lists like `1,3,5`

## Configuration

### Homebrew packages
Edit `core/Brewfile` to add/remove apps. Custom casks are in the `traktuner/tap` tap.

### macOS settings
Modify `utils/03-macos.sh` for personal preferences. Settings are organized by category (UI/UX, Finder, Dock, Safari, etc.).

### SSH Keys & General Configuration
Edit `utils/config.properties` to customize:
```properties
# SMB server for SSH key deployment
SMB_SERVER="<your-smb-server>"
SMB_USER_PATH="<private-share>/ssh"
SMB_MOUNT_POINT="/Volumes/ssh"

# Wallpaper path
WALLPAPER_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/wallpaper/default.jpeg"

# Time Machine preferences
TM_ENABLED=true
TM_AUTO_BACKUP=true
```

### T3 Xcode Worker

`utils/14-xcode-worker.sh` installs a pinned `XcodeBuildMCP` worker on this Mac.
It does not open a build daemon or grant a remote shell: the later
`t3-xcode-auth` step from the T3 container installs a restricted forced-command
key that can only invoke the worker below the configured Mac workspace root.

The container initiates SSH only for an Xcode MCP operation. Both the mounted
server workspace and the Mac must contain the same source tree at their mapped
roots; this bridge maps relative paths but does not synchronize files.

The installer is safe to re-run: it keeps `XcodeBuildMCP` at the configured pin
and refreshes the user LaunchAgent. It leaves Remote Login unchanged by default.
Set `T3_XCODE_ENABLE_REMOTE_LOGIN=true` in `utils/config.properties` only when
this Mac should accept SSH from the T3 host. After the Mac bootstrap, an
authorized T3 deployment establishes the dedicated key with:

```bash
docker exec -it t3code t3-xcode-auth <mac-user>@<mac-host>
```

Do not store the Mac workspace path, T3 host, SSH private key, or credentials in
this repository.

### agent-rack MCP

`utils/15-agent-rack.sh` installs the pinned stock
[`agent-rack`](https://github.com/lakpriya1s/agent-rack) npm package (an MCP
server that drives claude, codex, and opencode CLI agents as MCP tools) and
registers it with every installed local harness through agent-rack's own
official idempotent `install` and `cp` commands — never by hand-editing client
configs in this repo. The version is pinned in `utils/config.properties`
(`AGENT_RACK_VERSION`); update it deliberately, do not float to `latest`.

The script is safe to re-run. It also raises the stock
`security.defaultTimeoutSeconds` from 600 to 43200 (12h) because autonomous
sessions here run for many hours, and sets `security.maxConcurrentSessions`.
No LaunchAgent or daemon is created: agent-rack runs over stdio and is
started by each MCP client on demand.

## Security

- Time Machine snapshot before making changes
- **Trap-based cleanup**: Automatic unmounting of SMB shares and credential clearing on script exit/interrupt
- SSH key permissions automatically set (600/644)
- No passwords exposed in process list
- Full Disk Access verified before modifying protected settings
- **Rollback support**: Automatic offer to restore from Time Machine snapshot if scripts fail

## Logs

All output is logged to `/tmp/macos-config.log` with timestamps.

## Maintenance

Dependency updates are automated via Renovate (weekly, Monday mornings).

```bash
# Manual Homebrew maintenance
brew update && brew upgrade && brew cleanup

# List Time Machine snapshots
tmutil listlocalsnapshots /

# Restore from snapshot (requires reboot)
# tmutil restore -s "Snapshot-name" /
```

## Configuration Files

### config.properties (General Settings)
Used by `03-macos.sh` and `04-ssh-keys.sh` for customizable settings like SMB server, wallpaper, and Time Machine preferences.

### deploy.properties (CrashPlan Only)
CrashPlan-specific deployment configuration. This file is copied directly to `/Library/Application Support/CrashPlan/` during setup.

## Notes on macOS Tahoe (26)

- `com.apple.screensaver askForPassword` is deprecated - use Lock Screen settings or MDM profiles
- `com.apple.SoftwareUpdate ScheduleFrequency` has no effect since Catalina
- Safari defaults require Full Disk Access for Terminal
- Window tiling margins can be controlled via `com.apple.WindowManager`
- macOS Tahoe is the last version supporting Intel Macs
