"""Exercise restore operations with disposable data and no real credentials."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "utils" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


policy = load_module("policy", "validate-agent-rack-policy.py")
sources = load_module("sources", "validate-harness-sources.py")


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def pair(self):
        agents = {
            "codex_worker": {
                "command": "codex",
                "args": ["-c", "mcp_servers.agent-rack.enabled=false"],
                "env": {"ONCLOUD_AGENT_RACK_WORKER": "1"},
            }
        }
        config = {"allowedWorkspaces": sorted(policy.REQUIRED_WORKSPACES), "agents": agents}
        return (self.write("config.json", json.dumps(config)),
                self.write("profiles.json", json.dumps({"agents": agents})))

    def test_valid_policy_pair(self):
        self.assertEqual(policy.validate(*self.pair()), [])

    def test_invalid_alias_in_either_live_config_or_profiles_is_rejected(self):
        for index in (0, 1):
            with self.subTest(index=index):
                pair = self.pair()
                path = pair[index]
                path.write_text(path.read_text().replace("mcp_servers.agent-rack", "mcp_servers.agent_rack"))
                self.assertTrue(policy.validate(*pair))

    def test_missing_mounted_workspace_is_rejected(self):
        config, profiles = self.pair()
        data = json.loads(config.read_text())
        data["allowedWorkspaces"] = ["/workspace"]
        config.write_text(json.dumps(data))
        self.assertTrue(policy.validate(config, profiles))

    def test_absolute_cli_paths_still_require_child_restrictions(self):
        config, profiles = self.pair()
        for command in ("/opt/homebrew/bin/codex", "/opt/homebrew/bin/opencode"):
            with self.subTest(command=command):
                data = {"agents": {"worker": {"command": command, "args": [],
                        "env": {"ONCLOUD_AGENT_RACK_WORKER": "1"}}}}
                profiles.write_text(json.dumps(data))
                self.assertTrue(policy.validate(config, profiles))

    def test_harness_sources_without_optional_cursor_or_opencode_skill_root(self):
        self.write(".agents/skills/example/SKILL.md", "---\nname: example\ndescription: Example\n---\n")
        self.write(".claude/skills/example/SKILL.md", "---\ndescription: Example\n---\n")
        for name in (".codex/AGENTS.md", ".claude/CLAUDE.md", ".config/opencode/AGENTS.md"):
            self.write(name, f"{sources.START}\nShared policy\n{sources.END}\n")
        self.write(".config/agent-rack/agent-rack.profiles.json", '{"agents": {}}')
        self.write(".config/opencode/opencode.jsonc", "{}")
        self.assertEqual(sources.validate(self.root, self.root / ".config/agent-rack"), [])
        self.write(".agents/skills/example/upstream/SKILL.md", "---\nname: example\n---\n")
        self.assertTrue(sources.validate(self.root, self.root / ".config/agent-rack"))

    def sync_script(self):
        text = (ROOT / "utils/12-ai-config.sh").read_text()
        helpers = text[text.index("backup_target() {"):text.index("# Confirm destructive-ish save")]
        return "set -euo pipefail\nprint_info() { :; }\nprint_success() { :; }\nensure_directory() { mkdir -p \"$1\"; }\n" + helpers

    def run_sync(self, mode, source, destination):
        env = dict(os.environ, FIXTURE=str(self.root), MODE=mode)
        command = self.sync_script() + '\nMOUNT_POINT="$FIXTURE/share"\nSENSITIVE_BASENAMES="config.json"\nsync_tool fixture "$FIXTURE/local" skills config.json\n'
        return subprocess.run(["bash", "-c", command], env=env, capture_output=True, text=True)

    def test_pull_removes_stale_entries_backs_up_and_converges(self):
        self.write("share/fixture/skills/current/SKILL.md", "new skill")
        self.write("local/skills/retired/SKILL.md", "old skill")
        self.write("share/fixture/config.json", "{}")
        result = self.run_sync("pull", None, None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "local/skills/retired").exists())
        backups = list((self.root / "local").glob("skills.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "retired/SKILL.md").read_text(), "old skill")
        before = {str(p): p.stat().st_mtime_ns for p in (self.root / "local").rglob("*") if p.is_file()}
        result = self.run_sync("pull", None, None)
        self.assertEqual(result.returncode, 0, result.stderr)
        after = {str(p): p.stat().st_mtime_ns for p in (self.root / "local").rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        self.assertEqual((self.root / "local/config.json").stat().st_mode & 0o777, 0o600)

    def test_save_preserves_previous_snapshot_and_removes_stale_entries(self):
        self.write("local/skills/current/SKILL.md", "new skill")
        self.write("share/fixture/skills/retired/SKILL.md", "old skill")
        result = self.run_sync("save", None, None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "share/fixture/skills/retired").exists())
        backups = list((self.root / "share/fixture").glob("skills.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertTrue((backups[0] / "retired/SKILL.md").exists())
        self.assertEqual(self.run_sync("save", None, None).returncode, 0)
        self.assertEqual(list((self.root / "share/fixture").glob("skills.backup.*")), backups)

    def test_unchanged_sensitive_file_permissions_are_repaired(self):
        self.write("share/fixture/config.json", "{}")
        path = self.write("local/config.json", "{}")
        path.chmod(0o644)
        self.assertEqual(self.run_sync("pull", None, None).returncode, 0)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_version_guard_allows_brew_updates_and_preserves_arguments(self):
        brew = self.write("brew-opencode", "#!/bin/sh\nif [ \"$1\" = --version ]; then echo 1.18.30; else printf 'brew:%s\\n' \"$@\"; fi\n")
        stable = self.write(".local/share/opencode/1.18.20/opencode", "#!/bin/sh\nprintf 'stable:%s\\n' \"$@\"\n")
        brew.chmod(0o755)
        stable.chmod(0o755)
        wrapper = (ROOT / "utils/opencode-wrapper.sh").read_text().replace("/opt/homebrew/opt/opencode/bin/opencode", str(brew))
        path = self.write("wrapper", wrapper)
        env = dict(os.environ, HOME=str(self.root))
        def run():
            return subprocess.run(["sh", str(path), "with space"], env=env, capture_output=True, text=True)
        self.assertEqual(run().stdout, "stable:with space\n")
        brew.write_text(brew.read_text().replace("1.18.30", "1.18.31"))
        self.assertEqual(run().stdout, "brew:with space\n")
        brew.write_text(brew.read_text().replace("1.18.31", "1.18.30"))
        stable.unlink()
        self.assertEqual(run().returncode, 78)

    def test_agent_rack_delegates_all_harness_writes_to_infra_installer(self):
        """The macOS wrapper must invoke only the authoritative package writer."""
        home = self.root / "home"
        source = self.root / "infra"
        binaries = self.root / "bin"
        log = self.root / "calls.log"
        installer = source / "scripts/install-local-harness.py"
        builder = source / "scripts/build-harness-release.py"
        installer.parent.mkdir(parents=True)
        installer.write_text("# mocked by PATH python3\n")
        builder.write_text("# mocked by PATH python3\n")
        (home / ".local/share/opencode/1.18.20").mkdir(parents=True)
        stable = home / ".local/share/opencode/1.18.20/opencode"
        stable.write_text("#!/bin/sh\n")
        stable.chmod(0o755)
        (home / ".local/bin").mkdir(parents=True)
        (home / ".local/bin/opencode").write_text((ROOT / "utils/opencode-wrapper.sh").read_text())
        binaries.mkdir()
        for name, body in {
            "node": '#!/bin/sh\ncase "$1" in -p) echo 20 ;; -) echo 0.12.1 ;; --version) echo v20.0.0 ;; esac\n',
            "npm": f'#!/bin/sh\nprintf "npm:%s\\n" "$*" >> "{log}"\n',
            "python3": f'''#!/bin/sh
printf "python3:%s\\n" "$*" >> "{log}"
if [ "$1" = "{builder}" ]; then
  mkdir -p "$2/agent-rack" "$2/scripts"
  printf '{{"version":"0.12.1"}}\\n' > "$2/agent-rack/agent-rack-runtime.lock.json"
  : > "$2/scripts/harness-bundle.py"
  printf '{{"revision":"{'a' * 64}"}}\\n'
fi
''',
        }.items():
            path = binaries / name
            path.write_text(body)
            path.chmod(0o755)
        env = dict(os.environ, HOME=str(home), INFRA_HARNESS_SOURCE=str(source),
                   PATH=str(binaries) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", str(ROOT / "utils/15-agent-rack.sh")], env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"npm:install -g agent-rack@0.12.1 --no-fund --no-audit", log.read_text())
        self.assertIn(f"python3:{builder}", log.read_text())
        self.assertIn(f"python3:{installer} --help", log.read_text())
        self.assertIn(f"python3:{installer} --adopt", log.read_text())
        for path in (home / ".config/agent-rack/config.json", home / ".config/opencode/AGENTS.md",
                     home / ".codex/AGENTS.md", home / ".claude/CLAUDE.md",
                     home / ".agents/skills/.infra-managed-files.json"):
            self.assertFalse(path.exists(), f"the wrapper must not write managed state: {path}")

    def test_ai_config_only_syncs_owner_private_items_and_reconciles_after_pull(self):
        script = (ROOT / "utils/12-ai-config.sh").read_text()
        self.assertIn('CLAUDE_ITEMS=(settings.json)', script)
        self.assertIn('CLAUDE_DESKTOP_ITEMS=(claude_desktop_config.json)', script)
        self.assertIn('CODEX_ITEMS=(config.toml hooks.json auth.json)', script)
        self.assertIn('OPENCODE_ITEMS=(opencode.jsonc)', script)
        self.assertNotIn('sync_tool "agents"', script)
        self.assertNotIn('sync_tool "agent-rack"', script)
        self.assertNotIn('npm install', script)
        self.assertIn('utils/15-agent-rack.sh" --check-source', script)
        self.assertIn('utils/15-agent-rack.sh"', script)

    def test_check_source_verifies_cached_release_before_lock_read(self):
        script = (ROOT / "utils/15-agent-rack.sh").read_text()
        self.assertIn('CHECK_SOURCE_ONLY=false', script)
        self.assertIn('harness-bundle.py" verify', script)
        self.assertIn('"${cached%/*}" == "$cache_root/releases"', script)
        verify_index = script.index('harness-bundle.py" verify')
        lock_index = script.index('read_runtime_lock "$cached/agent-rack/agent-rack-runtime.lock.json"')
        self.assertLess(verify_index, lock_index)
        self.assertIn('const version = lock.version;', script)

    def test_check_source_rejects_missing_or_malformed_live_source(self):
        home = self.root / 'home'
        env = dict(os.environ, HOME=str(home), INFRA_HARNESS_SOURCE=str(self.root / 'missing'))
        command = ['bash', str(ROOT / 'utils/15-agent-rack.sh'), '--check-source']
        self.assertNotEqual(subprocess.run(command, env=env, capture_output=True, text=True).returncode, 0)
        malformed = self.root / 'malformed/scripts'
        malformed.mkdir(parents=True)
        (malformed / 'install-local-harness.py').write_text('')
        (malformed / 'build-harness-release.py').write_text('raise SystemExit(3)\n')
        env['INFRA_HARNESS_SOURCE'] = str(malformed.parent)
        self.assertNotEqual(subprocess.run(command, env=env, capture_output=True, text=True).returncode, 0)
        releases = home / '.local/share/infra-harness/releases/not-a-digest'
        (releases / 'scripts').mkdir(parents=True)
        (releases / 'agent-rack').mkdir()
        for path in (releases / 'scripts/apply-harness.py', releases / 'scripts/harness-bundle.py',
                     releases / '.bundle-manifest.json', releases / 'agent-rack/agent-rack-runtime.lock.json'):
            path.write_text('{}')
        current = home / '.local/share/infra-harness/current'
        current.symlink_to('releases/not-a-digest')
        env['INFRA_HARNESS_SOURCE'] = str(self.root / 'missing')
        self.assertNotEqual(subprocess.run(command, env=env, capture_output=True, text=True).returncode, 0)

    def test_wrapper_is_restored_when_authoritative_installer_fails(self):
        home, source, binaries = self.root / 'home', self.root / 'infra', self.root / 'bin'
        scripts = source / 'scripts'
        scripts.mkdir(parents=True)
        (scripts / 'install-local-harness.py').write_text('''import sys
if '--help' in sys.argv: raise SystemExit(0)
raise SystemExit(7)
''')
        (scripts / 'build-harness-release.py').write_text('''import json, pathlib, sys
d = pathlib.Path(sys.argv[1]); (d / 'agent-rack').mkdir(parents=True); (d / 'scripts').mkdir()
(d / 'agent-rack/agent-rack-runtime.lock.json').write_text('{"version":"0.12.1"}')
(d / 'scripts/harness-bundle.py').write_text('raise SystemExit(0)')
print(json.dumps({'revision': 'b' * 64}))
''')
        target = home / '.local/bin/opencode'
        target.parent.mkdir(parents=True)
        target.write_text('old wrapper\n')
        target.chmod(0o700)
        stable = home / '.local/share/opencode/1.18.20/opencode'
        stable.parent.mkdir(parents=True)
        stable.write_text('#!/bin/sh\n'); stable.chmod(0o755)
        binaries.mkdir()
        for name, body in {
            'node': '#!/bin/sh\ncase "$1" in -p) echo 20 ;; -) echo 0.12.1 ;; esac\n',
            'npm': '#!/bin/sh\nexit 0\n',
        }.items():
            path = binaries / name; path.write_text(body); path.chmod(0o755)
        env = dict(os.environ, HOME=str(home), INFRA_HARNESS_SOURCE=str(source),
                   PATH=str(binaries) + os.pathsep + os.environ['PATH'])
        result = subprocess.run(['bash', str(ROOT / 'utils/15-agent-rack.sh')], env=env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), 'old wrapper\n')
        self.assertEqual(target.stat().st_mode & 0o777, 0o700)

    def test_restore_preflight_and_handoff_preserve_override_and_skip_legacy_assets(self):
        home = self.root / 'home'
        fixture = self.root / 'fixture'
        log = self.root / 'restore.log'
        self.write('fixture/core/functions.sh', '''
print_info() { :; }; print_success() { :; }; print_error() { :; }
ensure_directory() { mkdir -p "$1"; }
smb_cleanup() { :; }; get_smb_credentials() { :; }; unmount_stale_share() { :; }
mount_smb_share() { echo mount >> "$PROBE_LOG"; }
ask_for_confirmation() { :; }; answer_is_yes() { return 0; }
''')
        self.write('fixture/utils/config.properties',
                   f'INFRA_HARNESS_SOURCE=/stale/default\nSMB_AI_MOUNT_POINT="{self.root}/share"\n')
        self.write('fixture/utils/12-ai-config.sh', (ROOT / 'utils/12-ai-config.sh').read_text())
        self.write('fixture/utils/15-agent-rack.sh', '''
set -eu
echo "harness:${1:-apply}:$INFRA_HARNESS_SOURCE" >> "$PROBE_LOG"
if [ "${1:-}" = --check-source ]; then exit "$PROBE_PREFLIGHT_RC"; fi
test -f "$HOME/.config/opencode/opencode.jsonc"
exit "${PROBE_APPLY_RC:-0}"
''')
        self.write('share/opencode/opencode.jsonc', '{}')
        self.write('share/opencode/plugins/legacy.ts', 'must not restore')
        self.write('share/agents/skills/legacy/SKILL.md', 'must not restore')
        self.write('share/agent-rack/config.json', 'must not restore')
        env = dict(os.environ, HOME=str(home), ROOT_DIR=str(fixture),
                   INFRA_HARNESS_SOURCE='/chosen/infra', PROBE_LOG=str(log), PROBE_PREFLIGHT_RC='1')
        def run(mode):
            return subprocess.run(['bash', str(fixture / 'utils/12-ai-config.sh'), mode],
                                  env=env, capture_output=True, text=True)
        self.assertNotEqual(run('pull').returncode, 0)
        self.assertEqual(log.read_text().splitlines(), ['harness:--check-source:/chosen/infra'])
        self.assertFalse(home.exists())
        log.unlink()
        env['PROBE_PREFLIGHT_RC'] = '0'
        result = run('pull')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text().splitlines(),
                         ['harness:--check-source:/chosen/infra', 'mount', 'harness:apply:/chosen/infra'])
        self.assertFalse((home / '.config/opencode/plugins').exists())
        self.assertFalse((home / '.agents').exists())
        self.assertFalse((home / '.config/agent-rack').exists())
        self.assertEqual((home / '.config/opencode/opencode.jsonc').stat().st_mode & 0o777, 0o600)
        # A late shared-harness failure restores every private item, including
        # paths that were absent before the failed pull.
        private = {
            'claude/settings.json': 'old claude',
            'claude-desktop/claude_desktop_config.json': 'old desktop',
            'codex/config.toml': 'old codex',
            'codex/hooks.json': 'old hooks',
            'codex/auth.json': 'old auth',
            'opencode/opencode.jsonc': 'old opencode',
        }
        for name, old in private.items():
            share = self.root / 'share' / name
            share.parent.mkdir(parents=True, exist_ok=True)
            share.write_text('new ' + old)
        (home / '.codex').mkdir(parents=True, exist_ok=True)
        (home / '.codex/auth.json').write_text('local auth')
        (home / '.config/opencode/opencode.jsonc').unlink()
        env['PROBE_APPLY_RC'] = '1'
        self.assertNotEqual(run('pull').returncode, 0)
        self.assertEqual((home / '.codex/auth.json').read_text(), 'local auth')
        self.assertFalse((home / '.claude/settings.json').exists())
        self.assertFalse((home / '.codex/config.toml').exists())
        self.assertFalse((home / '.codex/hooks.json').exists())
        self.assertFalse((home / '.config/opencode/opencode.jsonc').exists())
        log.unlink()
        result = run('save')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text().splitlines(), ['mount'])


if __name__ == "__main__":
    unittest.main()
