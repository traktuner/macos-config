#!/usr/bin/env python3
"""Validate an agent-rack config and profiles before Mac restore or use."""

import json
import sys
from pathlib import Path


REQUIRED_WORKSPACES = {
    "/workspace",
    "/data/t3/worktrees",
    str(Path.home() / "Netzlaufwerke/developer"),
    str(Path.home() / ".t3/worktrees"),
}
CANONICAL_MCP = "agent-rack"
INVALID_MCP = "agent_rack"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: top-level JSON value must be an object")
    return value


def validate(config_path: Path, profiles_path: Path) -> list[str]:
    errors = validate_document(config_path, config_path)
    errors.extend(validate_document(config_path, profiles_path))
    return errors


def validate_document(config_path: Path, profiles_path: Path) -> list[str]:
    config = load(config_path)
    profiles = load(profiles_path)
    errors: list[str] = []

    workspaces = config.get("allowedWorkspaces")
    if not isinstance(workspaces, list) or not all(isinstance(item, str) for item in workspaces):
        errors.append(f"{config_path}: allowedWorkspaces must be a string list")
    else:
        missing = sorted(REQUIRED_WORKSPACES - set(workspaces))
        if missing:
            errors.append(f"{config_path}: missing required workspaces: {', '.join(missing)}")

    agents = profiles.get("agents")
    if not isinstance(agents, dict):
        errors.append(f"{profiles_path}: agents must be an object")
        return errors

    for name, agent in agents.items():
        if not isinstance(agent, dict):
            errors.append(f"{profiles_path}: agent {name} must be an object")
            continue
        args = agent.get("args", [])
        env = agent.get("env", {})
        if not isinstance(args, list) or not all(isinstance(item, str) for item in args):
            errors.append(f"{profiles_path}: agent {name} args must be a string list")
            continue
        if not isinstance(env, dict):
            errors.append(f"{profiles_path}: agent {name} env must be an object")
            continue

        if any(f"mcp_servers.{INVALID_MCP}." in item for item in args):
            errors.append(f"{profiles_path}: {name} contains invalid Codex MCP name {INVALID_MCP}")
        command = Path(str(agent.get("command", ""))).name
        if command == "codex" and env.get("ONCLOUD_AGENT_RACK_WORKER") == "1":
            override = f"mcp_servers.{CANONICAL_MCP}.enabled=false"
            if args.count(override) != 1:
                errors.append(f"{profiles_path}: {name} must contain {override} exactly once")

        content = env.get("OPENCODE_CONFIG_CONTENT")
        if not isinstance(content, str):
            if command == "opencode" and env.get("ONCLOUD_AGENT_RACK_WORKER") == "1":
                errors.append(f"{profiles_path}: {name} is missing its OpenCode child configuration")
            continue
        try:
            child = json.loads(content)
        except json.JSONDecodeError as error:
            errors.append(f"{profiles_path}: OpenCode config for {name} is invalid JSON: {error}")
            continue
        mcp = child.get("mcp") if isinstance(child, dict) else None
        if not isinstance(mcp, dict):
            errors.append(f"{profiles_path}: OpenCode config for {name} has no MCP object")
            continue
        if INVALID_MCP in mcp:
            errors.append(f"{profiles_path}: {name} contains invalid OpenCode MCP name {INVALID_MCP}")
        if command == "opencode" and env.get("ONCLOUD_AGENT_RACK_WORKER") == "1":
            canonical = mcp.get(CANONICAL_MCP)
            if not isinstance(canonical, dict) or canonical.get("enabled") is not False:
                errors.append(f"{profiles_path}: {name} must disable {CANONICAL_MCP}")

    return errors


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {Path(sys.argv[0]).name} config.json agent-rack.profiles.json", file=sys.stderr)
        return 2
    try:
        errors = validate(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"invalid agent-rack policy: {error}", file=sys.stderr)
        return 2
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("agent-rack restore policy valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
