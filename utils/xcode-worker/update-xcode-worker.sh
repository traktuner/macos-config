#!/usr/bin/env bash
set -Eeuo pipefail

npm_prefix="${T3_XCODE_NPM_PREFIX:-$HOME/.local/share/t3-xcode-worker/npm}"
version="${XCODEBUILDMCP_VERSION:-2.6.2}"
mkdir -p "$npm_prefix"
exec npm install -g --prefix "$npm_prefix" --no-audit --no-fund "xcodebuildmcp@$version"
