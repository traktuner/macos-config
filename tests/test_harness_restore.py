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
        self.root = Path(self.temp.name)

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


if __name__ == "__main__":
    unittest.main()
