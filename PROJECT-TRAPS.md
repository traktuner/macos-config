# Project traps

- **Do not treat reinstalling Xcode as a complete developer backup.** Xcode archives, provisioning profiles, and signing certificates are separate from the Xcode app. Back up Archives and profiles, and export certificates as `.p12` files before erasing the Mac. See `utils/06-backup-before-reinstall.sh`.
- **Do not install UrBackup through `utils/07-manual-apps.sh`.** The `urbackup-client` cask in `core/Brewfile` installs the current macOS package from the trusted tap. The manual script must remain a no-op unless a future app is genuinely unavailable through Homebrew.
- **Do not assume Logic or audio plugin presets live only under `~/Library/Audio`.** On this Mac, Logic content is under `/Library/Application Support/Logic`, Nexus content is under `/Library/Audio/Presets`, and Sylenth1 soundbanks and its data folder are under `~/Library/Application Support/LennarDigital/Sylenth1`; back up all three locations before reinstalling macOS (`utils/06-backup-before-reinstall.sh`).
- **Do not commit a user-specific backup destination.** Keep the script portable with `$HOME`, an argument, or `BACKUP_DESTINATION`.
- **Do not execute utility scripts directly from the SMB-mounted repo, and do not hardcode mount sub-paths in scripts.** The share does not persist exec bits and the real backup mount is `~/Netzlaufwerke/tom/restore/2026`. Call scripts via `bash <script>` (never prefixed with `sudo`, which breaks `$HOME`-based defaults), and keep user-specific sub-paths in `utils/config.properties` (`BACKUP_RESTORE_SUBPATH`; the generic fallback `restore/2026` stays in the script).
- **Do not trust `git stash`/`git gc`/`git commit` on the SMB-mounted repo checkout to work reliably.** SMB-locked `.git/objects` sub-directories can silently make specific fan-out dirs read-only for macOS git, breaking `git stash push`/`git commit` with `insufficient permission for adding an object`. Recovery: `mv <dir> <dir>_old && mkdir <dir>`, then `cp` (not `mv`) each object into the fresh dir; the objects themselves stay SMB-locked, but the new dir is writable and `git fsck` is clean afterwards. Leftover `<dir>_old` remnants with locked objects are harmless — git ignores foreign dirs in `.git/objects` (deleted from SMB side later).

- **Do not let an agent-rack reinstall erase the synchronous parallel join guarantee.** Keep `agent-rack-join-patch.mjs` in both `utils/15-agent-rack.sh`'s policy list and `utils/12-ai-config.sh`'s backup list, then execute it after the pinned package install (`utils/15-agent-rack.sh`).

- **Do not install an agent-rack policy that only permits `/workspace`.** Local
  audit repositories live under `/Users/thomas/Developer` and
  `/Users/thomas/Netzlaufwerke/developer`; stock agent-rack rejects a worker
  before launch when its workspace is absent. `15-agent-rack.sh` must validate
  the canonical universal list before it copies `config.json`
  (`stacks/t3code/agent-rack-policies/validate-agent-rack-workspaces.py`).

- **Do not restore an agent-rack policy with `mcp_servers.agent_rack.enabled=false`.** Codex reads it as a separate incomplete MCP server and aborts every worker with `invalid transport`. `utils/15-agent-rack.sh` must validate both canonical JSON files before copying them; the only valid child override is `mcp_servers.agent-rack.enabled=false`.

- **Use the SMB checkout as the Mac configuration source.** Resolve the live checkout before editing or publishing. The former `Developer/_repos` checkout is stale. `utils/config.properties` and `utils/15-agent-rack.sh` must use the mounted Infra checkout or a validated restored policy directory.

- **Keep one active entry point per shared skill.** OpenCode scans nested `SKILL.md` files and multiple global roots. Duplicate IDs generate warnings. Preserve Claude adaptations, use `~/.agents/skills` for shared skills, and quarantine duplicate OpenCode copies and nested entry points. Duplicate skills did not cause the separately reproduced OpenCode 1.18.30 prompt crash.

- **Copy agent-rack skills to the explicit shared directory.** In agent-rack 0.12.1, `cp --target codex` writes to `~/.codex/skills`. Use the shared `~/.agents/skills` destination and quarantine legacy copies to keep harness sources consistent (`utils/15-agent-rack.sh`).

- **Keep the OpenCode 1.18.30 workaround restorable and version-specific.** The observed `SystemPrompt.environment` crash happened before the Lumo request. `utils/opencode-wrapper.sh` selects verified 1.18.20 only for 1.18.30. Other Homebrew versions remain eligible and need a real prompt test. A newer version is not proven fixed merely because the wrapper permits it.
