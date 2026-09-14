#!/bin/sh
# Keep the known-bad OpenCode 1.18.30 out of every harness while allowing
# Homebrew to install and expose later versions automatically.
set -eu

STABLE="${HOME}/.local/share/opencode/1.18.20/opencode"
BREW="/opt/homebrew/opt/opencode/bin/opencode"

if [ -x "$BREW" ]; then
  VERSION=$("$BREW" --version 2>/dev/null || true)
  case "$VERSION" in
    1.18.30*)
      if [ -x "$STABLE" ]; then
        exec "$STABLE" "$@"
      fi
      echo "OpenCode ${VERSION} is blocked by the known SystemPrompt regression; restore ${STABLE}." >&2
      exit 78
      ;;
    *)
      exec "$BREW" "$@"
      ;;
  esac
fi

if [ -x "$STABLE" ]; then
  exec "$STABLE" "$@"
fi

echo "No usable OpenCode binary found. Install Homebrew OpenCode or restore ${STABLE}." >&2
exit 127
