#!/usr/bin/env bash
set -euo pipefail

source "$ROOT_DIR/core/functions.sh"
print_info "Configuring Firefox extensions and preferences via policies.json"

FIREFOX_APP="/Applications/Firefox.app"
DIST_DIR="$FIREFOX_APP/Contents/Resources/distribution"
POLICIES_FILE="$DIST_DIR/policies.json"

if [[ ! -d "$FIREFOX_APP" ]]; then
  print_error "Firefox not found at $FIREFOX_APP"
  exit 1
fi

ensure_directory "$DIST_DIR" true

# Bypass Paywalls Clean: not on AMO, requires direct XPI + signature override
BPC_XPI="https://gitflic.ru/project/magnolia1234/bpc_uploads/blob/raw?file=bypass_paywalls_clean-latest.xpi&inline=false"

print_info "Writing policies.json..."
sudo tee "$POLICIES_FILE" > /dev/null <<POLICIES
{
  "policies": {
    "Preferences": {
      "browser.ml.chat.provider": {
        "Value": "https://lumo.proton.me/u/0/",
        "Status": "default"
      },
      "xpinstall.signatures.required": {
        "Value": false,
        "Status": "default"
      },
      "gfx.webrender.all": {
        "Value": true,
        "Status": "default"
      },
      "media.hardware-video-decoding.force-enabled": {
        "Value": true,
        "Status": "default"
      },
      "privacy.trackingprotection.enabled": {
        "Value": true,
        "Status": "locked"
      },
      "privacy.trackingprotection.socialtracking.enabled": {
        "Value": true,
        "Status": "locked"
      },
      "dom.security.https_only_mode": {
        "Value": true,
        "Status": "locked"
      },
      "datareporting.healthreport.uploadEnabled": {
        "Value": false,
        "Status": "locked"
      },
      "toolkit.telemetry.enabled": {
        "Value": false,
        "Status": "locked"
      },
      "app.shield.optoutstudies.enabled": {
        "Value": false,
        "Status": "locked"
      },
      "browser.aboutConfig.showWarning": {
        "Value": false,
        "Status": "default"
      },
      "browser.tabs.crashReporting.sendReport": {
        "Value": false,
        "Status": "default"
      }
    },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      },
      "addon@darkreader.org": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi"
      },
      "78272b6fa58f4a1abaac99321d503a20@proton.me": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi"
      },
      "vpn@proton.ch": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/proton-vpn-firefox-extension/latest.xpi"
      },
      "{d8d0bc2b-45c2-404d-bb00-ce54305fc39c}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/flag-cookies/latest.xpi"
      },
      "jid1-q4sG8pYhq8KGHs@jetpack": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/adblock-for-youtube/latest.xpi"
      },
      "{64b6e993-27a4-494c-8173-3ace9a4b30c5}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ig-downloader/latest.xpi"
      },
      "jid1-OY8Xu5BsKZQa6A@jetpack": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/myjdownloader-browser-extensi/latest.xpi"
      },
      "addon@karakeep.app": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/karakeep/latest.xpi"
      },
      "{08f0f80f-2b26-4809-9267-287a5bdda2da}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/tubearchivist-companion/latest.xpi"
      },
      "magnolia@12.34": {
        "installation_mode": "normal_installed",
        "install_url": "$BPC_XPI"
      }
    }
  }
}
POLICIES

sudo chown root:wheel "$POLICIES_FILE"
sudo chmod 644 "$POLICIES_FILE"

print_success "Firefox policies.json installed (extensions + preferences)"
print_info "Changes take effect on next Firefox launch"
