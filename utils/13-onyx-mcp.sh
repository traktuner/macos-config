#!/usr/bin/env bash
set -euo pipefail

# Configure the same authenticated Onyx Streamable HTTP MCP for every local
# desktop/CLI harness. The token is deliberately stored only in private local
# configuration files and the macOS Keychain; the private SMB tresor carries
# those files through utils/12-ai-config.sh.

ONYX_MCP_URL="${ONYX_MCP_URL:-https://onyx.oncloud.at/mcp}"
ONYX_KEYCHAIN_SERVICE="${ONYX_KEYCHAIN_SERVICE:-onyx-mcp-token}"

onyx_token="$(launchctl getenv ONYX_TOKEN 2>/dev/null || true)"
if [[ -z "$onyx_token" ]]; then
  onyx_token="$(security find-generic-password -s "$ONYX_KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
fi
if [[ -z "$onyx_token" ]]; then
  printf 'ONYX_TOKEN is unavailable in launchctl and Keychain service %s\n' "$ONYX_KEYCHAIN_SERVICE" >&2
  exit 1
fi

security add-generic-password \
  -U \
  -s "$ONYX_KEYCHAIN_SERVICE" \
  -a "$USER" \
  -w "$onyx_token" >/dev/null

export ONYX_MCP_URL
export ONYX_TOKEN="$onyx_token"

node <<'NODE'
const fs = require("fs");
const path = require("path");

const home = process.env.HOME;
const url = process.env.ONYX_MCP_URL;
const token = process.env.ONYX_TOKEN;
if (!home || !url || !token) throw new Error("missing Onyx configuration input");

function privateWrite(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.onyx-new`;
  fs.writeFileSync(temporary, content, { mode: 0o600 });
  fs.chmodSync(temporary, 0o600);
  fs.renameSync(temporary, file);
  fs.chmodSync(file, 0o600);
}

function updateJson(file, updater) {
  let value = {};
  if (fs.existsSync(file)) value = JSON.parse(fs.readFileSync(file, "utf8"));
  updater(value);
  privateWrite(file, `${JSON.stringify(value, null, 2)}\n`);
}

const authorization = `Bearer ${token}`;

const codexFile = path.join(home, ".codex", "config.toml");
let codex = fs.readFileSync(codexFile, "utf8");
const codexSection = `[mcp_servers.onyx]\nurl = ${JSON.stringify(url)}\nhttp_headers = { Authorization = ${JSON.stringify(authorization)} }`;
if (/\[mcp_servers\.onyx\][\s\S]*?(?=\n\[|$)/.test(codex)) {
  codex = codex.replace(/\[mcp_servers\.onyx\][\s\S]*?(?=\n\[|$)/, codexSection);
} else {
  codex = `${codex.trimEnd()}\n\n${codexSection}\n`;
}
privateWrite(codexFile, codex);

const claudeCodeFile = path.join(home, ".claude.json");
updateJson(claudeCodeFile, (value) => {
  value.mcpServers ??= {};
  value.mcpServers.onyx = {
    type: "http",
    url,
    headers: { Authorization: authorization },
  };
});

const claudeDesktopFile = path.join(
  home,
  "Library",
  "Application Support",
  "Claude",
  "claude_desktop_config.json",
);
updateJson(claudeDesktopFile, (value) => {
  value.mcpServers ??= {};
  value.mcpServers.onyx = {
    url,
    headers: { Authorization: authorization },
  };
});

const openCodeFile = path.join(home, ".config", "opencode", "opencode.jsonc");
let openCode = fs.readFileSync(openCodeFile, "utf8");
const onyxStart = openCode.indexOf('"onyx"');
if (onyxStart < 0) throw new Error("OpenCode onyx MCP block is missing");
const headerStart = openCode.indexOf('"Authorization"', onyxStart);
if (headerStart < 0) throw new Error("OpenCode onyx Authorization header is missing");
const headerTail = openCode.slice(headerStart);
const headerMatch = headerTail.match(/"Authorization"\s*:\s*"[^"]*"/);
if (!headerMatch) throw new Error("OpenCode onyx Authorization header is malformed");
openCode =
  openCode.slice(0, headerStart) +
  headerTail.replace(
    headerMatch[0],
    `"Authorization": ${JSON.stringify(authorization)}`,
  );
privateWrite(openCodeFile, openCode);
NODE

unset ONYX_TOKEN
unset onyx_token

printf 'Configured authenticated Onyx MCP for Codex/ChatGPT, Claude Code, Claude Desktop, and OpenCode.\n'
printf 'Fully quit and reopen the desktop apps so they reload MCP configuration.\n'
