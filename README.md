# macOS Config

Automated configuration for new macOS installations.

## 🚀 Features

- **Modular Scripts**: Each aspect of configuration is split into separate scripts
- **Interactive Selection**: Choose which scripts to run
- **Robust Error Handling**: Retry mechanisms and comprehensive validation
- **Security**: Time Machine snapshots before critical changes

## 📋 Prerequisites

- macOS (tested on macOS 14+)
- Internet connection for Homebrew installation
- SMB access for SSH keys (optional)

## 🛠️ Installation

```bash
# Clone repository
git clone <your-repo-url>
cd macos-config

# Run bootstrap script
./bootstrap
```

## 📁 Project Structure

```
macos-config/
├── bootstrap              # Main script with interactive menu
├── core/
│   ├── Brewfile          # Homebrew packages and apps
│   └── functions.sh      # Shared functions
├── utils/
│   ├── 00-preflight.sh   # Time Machine snapshot, CrashPlan
│   ├── 01-install-rosetta2.sh
│   ├── 02-homebrew.sh    # Homebrew installation & packages
│   ├── 03-macos.sh       # macOS system configuration
│   ├── 04-ssh-keys.sh    # SSH keys from SMB share
│   ├── 05-config-profile.sh # Install configuration profile
│   └── 06-macos-update.sh   # System updates
└── renovate.json         # Automatic updates
```

## 🎯 Usage

1. **Full Installation**: Choose option `0` for all scripts
2. **Selective Installation**: Choose individual scripts or ranges
3. **Range Selection**: Use ranges like `1-3` or lists like `1,3,5`

## 🔧 Configuration

### Customize Homebrew packages
Edit `core/Brewfile` to add/remove apps.

### Customize macOS settings
Modify `utils/03-macos.sh` for personal preferences.

### SSH Keys
Configure the SMB path in `utils/04-ssh-keys.sh`.

## 🛡️ Security

- Time Machine snapshots before critical changes
- Secure password input for SMB access
- Automatic cleanup of sensitive data

## 🔄 Maintenance

The project is automatically updated by Renovate. For manual updates:

```bash
# Update Homebrew packages
brew update && brew upgrade

# Add new macOS settings
# Edit utils/03-macos.sh
```

## 📝 Logs

- Homebrew installation: `/tmp/homebrew-install.log`
- Time Machine snapshots: Automatically named with timestamp

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Create pull request

## 📄 License

[Your license here]
