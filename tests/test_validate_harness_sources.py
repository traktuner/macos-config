import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = REPOSITORY / "utils" / "validate-harness-sources.py"
SPEC = importlib.util.spec_from_file_location("validate_harness_sources", VALIDATOR_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class HarnessSourceValidationTests(unittest.TestCase):
    def staged_sources(self, root: Path) -> tuple[Path, Path]:
        home = root / "home"
        rack = root / "agent-rack"
        for skill_root in (
            home / ".agents/skills",
            home / ".claude/skills",
            home / ".cursor/skills",
            home / ".config/opencode/skills",
        ):
            skill_root.mkdir(parents=True)

        body = "Use stock agent-rack."
        policy = (
            f"{VALIDATOR.START}\n{body}\n{VALIDATOR.END}\n"
        )
        for path in (
            home / ".config/opencode/AGENTS.md",
            home / ".codex/AGENTS.md",
            home / ".claude/CLAUDE.md",
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(policy, encoding="utf-8")

        rack.mkdir()
        (rack / "agent-rack.profiles.json").write_text(
            json.dumps({"agents": {}}), encoding="utf-8"
        )
        (home / ".config/opencode/opencode.jsonc").write_text("{}\n", encoding="utf-8")
        return home, rack

    def test_accepts_agent_rack_only_claude_sources(self) -> None:
        with tempfile.TemporaryDirectory(prefix="harness-source-test-") as directory:
            home, rack = self.staged_sources(Path(directory))
            self.assertEqual(VALIDATOR.validate(home, rack), [])

    def test_rejects_legacy_native_claude_routing_and_agent(self) -> None:
        with tempfile.TemporaryDirectory(prefix="harness-source-test-") as directory:
            home, rack = self.staged_sources(Path(directory))
            claude_rules = home / ".claude/CLAUDE.md"
            claude_rules.write_text(
                claude_rules.read_text(encoding="utf-8")
                + "The user's primary coding harness is now OpenCode + Lumo Max\n"
                + "Use parallel Claude subagents.\n",
                encoding="utf-8",
            )
            agents = home / ".claude/agents"
            agents.mkdir()
            (agents / "opus-critical-reviewer.md").write_text("model: opus\n", encoding="utf-8")
            commands = home / ".claude/commands"
            commands.mkdir()
            (commands / "critical-review.md").write_text(
                "Route to opus-critical-reviewer.\n", encoding="utf-8"
            )

            errors = VALIDATOR.validate(home, rack)

            self.assertTrue(any("legacy native Claude routing" in error for error in errors))
            self.assertTrue(any("opus-critical-reviewer.md" in error for error in errors))
            self.assertTrue(any("critical-review.md" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
