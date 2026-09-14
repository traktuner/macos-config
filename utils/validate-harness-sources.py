#!/usr/bin/env python3
"""Validate the active Mac harness sources after restore and provisioning."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


START = "<!-- t3-docker:agent-rack-policy:start -->"
END = "<!-- t3-docker:agent-rack-policy:end -->"
SKILL_NAME = re.compile(r"^name:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*$", re.MULTILINE)
DESCRIPTION = re.compile(r"^description:\s*.+$", re.MULTILINE)


def frontmatter(path: Path) -> str:
    parts = path.read_text(encoding="utf-8").split("---", 2)
    if len(parts) != 3:
        raise ValueError(f"{path}: missing frontmatter")
    return parts[1]


def skill_ids(root: Path, *, require_name: bool) -> set[str]:
    if not root.is_dir():
        raise ValueError(f"missing skill root: {root}")
    nested = sorted(
        path
        for path in root.rglob("SKILL.md")
        if len(path.relative_to(root).parts) > 2
    )
    if nested:
        raise ValueError("nested SKILL.md entrypoints: " + ", ".join(map(str, nested)))

    result: set[str] = set()
    for path in sorted(root.glob("*/SKILL.md")):
        skill_id = path.parent.name
        metadata = frontmatter(path)
        if not DESCRIPTION.search(metadata):
            raise ValueError(f"{path}: missing description")
        match = SKILL_NAME.search(metadata)
        if require_name and not match:
            raise ValueError(f"{path}: missing valid name")
        allowed_names = {skill_id}
        if skill_id.startswith("agent-rack-"):
            allowed_names.add(skill_id.removeprefix("agent-rack-"))
        if match and match.group(1) not in allowed_names:
            raise ValueError(f"{path}: name does not match directory")
        result.add(skill_id)
    return result


def policy_body(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if text.count(START) != 1 or text.count(END) != 1:
        raise ValueError(f"{path}: managed policy markers are not exactly one pair")
    return text.split(START, 1)[1].split(END, 1)[0].strip()


def validate(home: Path, rack: Path) -> list[str]:
    errors: list[str] = []
    try:
        shared = skill_ids(home / ".agents/skills", require_name=True)
        claude = skill_ids(home / ".claude/skills", require_name=False)
        cursor = skill_ids(home / ".cursor/skills", require_name=True) if (home / ".cursor").exists() else None
        opencode_root = home / ".config/opencode/skills"
        opencode = skill_ids(opencode_root, require_name=True) if opencode_root.exists() else set()
        if shared != claude:
            errors.append("Claude and shared skill IDs differ")
        if cursor is not None and not shared.issubset(cursor):
            errors.append("Cursor is missing shared skill IDs")
        overlap = sorted(shared & opencode)
        if overlap:
            errors.append("OpenCode has duplicate shared skill IDs: " + ", ".join(overlap))
    except (OSError, ValueError) as error:
        errors.append(str(error))

    codex_skills = home / ".codex/skills"
    if any(codex_skills.glob("agent-rack-*/SKILL.md")):
        errors.append("Codex has agent-rack skills in the non-discovery root ~/.codex/skills")

    policy_paths = [
        home / ".config/opencode/AGENTS.md",
        home / ".codex/AGENTS.md",
        home / ".claude/CLAUDE.md",
    ]
    try:
        bodies = [policy_body(path) for path in policy_paths]
        if len({hashlib.sha256(body.encode()).hexdigest() for body in bodies}) != 1:
            errors.append("harness policy blocks differ")
    except (OSError, ValueError) as error:
        errors.append(str(error))

    profiles_path = rack / "agent-rack.profiles.json"
    try:
        profiles = json.loads(profiles_path.read_text(encoding="utf-8"))
        for name, agent in profiles.get("agents", {}).items():
            args = agent.get("args", [])
            if any("mcp_servers.agent_rack" in value for value in args):
                errors.append(f"{profiles_path}: {name} contains mcp_servers.agent_rack")
            content = agent.get("env", {}).get("OPENCODE_CONFIG_CONTENT")
            if isinstance(content, str) and "\"agent_rack\"" in content:
                errors.append(f"{profiles_path}: {name} contains OpenCode agent_rack")
    except (OSError, json.JSONDecodeError, AttributeError) as error:
        errors.append(f"{profiles_path}: invalid profiles: {error}")

    opencode_jsonc = home / ".config/opencode/opencode.jsonc"
    try:
        text = opencode_jsonc.read_text(encoding="utf-8")
        if '"agent_rack"' in text:
            errors.append(f"{opencode_jsonc}: contains invalid MCP key agent_rack")
    except OSError as error:
        errors.append(str(error))
    return errors


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {Path(sys.argv[0]).name} HOME AGENT_RACK_DIR", file=sys.stderr)
        return 2
    errors = validate(Path(sys.argv[1]), Path(sys.argv[2]))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("active harness sources valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
