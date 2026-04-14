#!/usr/bin/env python3
"""
Hook: protect-raw-data.py
Fires on PreToolUse for Bash, Write, and Edit.
Hard-blocks (exit 2) any operation that would write to raw_data/.
"""

import json
import sys
import os

WRITE_VERBS = {">", ">>", "write", "rm", "unlink", "mv", "cp", "del",
               "truncate", "tee", "touch", "mkdir", "install", "move", "copy"}

def check_bash(command: str) -> bool:
    """Return True (block) if command writes into raw_data/."""
    cmd_lower = command.lower()
    if "raw_data/" not in cmd_lower and "raw_data\\" not in cmd_lower:
        return False
    tokens = set(cmd_lower.split())
    return bool(tokens & WRITE_VERBS) or ">" in command

def check_path(path: str) -> bool:
    """Return True (block) if path is inside raw_data/."""
    normalized = path.replace("\\", "/").lower()
    return "/raw_data/" in normalized or normalized.endswith("/raw_data")

def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    tool = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})

    blocked = False

    if tool == "Bash":
        command = tool_input.get("command", "")
        if check_bash(command):
            blocked = True
            print(
                f"\n[BLOCKED] raw_data/ is strictly read-only.\n"
                f"Command attempted: {command[:200]}\n"
                f"All pipeline outputs must go to clean_data/.",
                file=sys.stderr
            )

    elif tool in ("Write", "Edit"):
        path = tool_input.get("file_path", "")
        if check_path(path):
            blocked = True
            print(
                f"\n[BLOCKED] raw_data/ is strictly read-only.\n"
                f"Attempted to write: {path}\n"
                f"All pipeline outputs must go to clean_data/.",
                file=sys.stderr
            )

    sys.exit(2 if blocked else 0)

if __name__ == "__main__":
    main()
