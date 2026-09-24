#!/usr/bin/env python3
"""
Hook: protect-raw-data.py
Fires on PreToolUse for Bash, PowerShell, Write, and Edit.
Hard-blocks (exit 2) any operation that would write to raw_data/.

Exempt download dirs accept NEW files only: deleting, moving, renaming, or
overwriting an existing file is blocked everywhere in raw_data/, exempt dirs
included. Changing an existing raw file requires the user to lift this hook.
"""

import json
import os
import re
import sys

# Bash + PowerShell verbs (lowercased) that can create or change files.
WRITE_VERBS = {">", ">>", "write", "rm", "unlink", "mv", "cp", "del",
               "truncate", "tee", "touch", "mkdir", "install", "move", "copy",
               "curl", "wget", "unzip", "tar", "7z",
               "set-content", "add-content", "out-file", "new-item", "copy-item",
               "cpi", "sc", "ac", "invoke-webrequest", "iwr", "expand-archive"}

# Destructive verbs are blocked ANYWHERE in raw_data, including exempt download dirs.
DESTRUCTIVE_VERBS = {"rm", "unlink", "del", "truncate", "mv", "move",
                     "remove-item", "ri", "rmdir", "rd", "erase",
                     "move-item", "mi", "rename-item", "ren", "rni",
                     "clear-content", "clc"}

# Flags that make an archive extraction overwrite existing files without asking.
ARCHIVE_VERBS = {"unzip", "tar", "7z", "expand-archive"}
OVERWRITE_FLAGS = {"-o", "-force", "-y", "-aoa", "--overwrite"}

# Narrow exception: NEW source downloads may be written into these subfolders only.
EXEMPT_DIRS = ("raw_data/sdwa_cws_pop", "raw_data/census", "raw_data/msha/part50")

NON_EXEMPT_RE = re.compile(
    r"raw_data/(?!" + "|".join(re.escape(d[len("raw_data/"):]) for d in EXEMPT_DIRS) + ")")
PATH_TOKEN_RE = re.compile(r"[^\s'\"=]+")


def _is_exempt(normalized: str) -> bool:
    return any(ex + "/" in normalized for ex in EXEMPT_DIRS)


def _to_os_path(token: str, cwd: str) -> str:
    """Map a command token (Git Bash /z/..., Windows Z:\\..., or relative) to an OS path."""
    t = token.strip("'\"").replace("\\", "/")
    m = re.match(r"^/([a-zA-Z])/(.*)$", t)
    if m:
        t = f"{m.group(1)}:/{m.group(2)}"
    if not os.path.isabs(t):
        t = os.path.join(cwd, t)
    return os.path.normpath(t)


def _overwrites_existing(command: str, cwd: str) -> bool:
    """True if a raw_data/ path in the command is an existing file, or is a directory
    that already holds a file with the same name as another path in the command."""
    tokens = PATH_TOKEN_RE.findall(command)
    raw_tokens = [t for t in tokens if "raw_data/" in t.replace("\\", "/").lower()]
    try:
        for rt in raw_tokens:
            p = _to_os_path(rt, cwd)
            if os.path.isfile(p):
                return True
            if os.path.isdir(p):
                for other in tokens:
                    if other is rt:
                        continue
                    name = os.path.basename(other.strip("'\"").replace("\\", "/").rstrip("/"))
                    if name and os.path.exists(os.path.join(p, name)):
                        return True
    except (OSError, ValueError):
        return True
    return False


def check_command(command: str, cwd: str) -> bool:
    """Return True (block) if a shell command writes into raw_data/ unsafely."""
    cmd_lower = command.lower().replace("\\", "/")
    if "raw_data/" not in cmd_lower:
        return False
    tokens = set(cmd_lower.split())
    # Always block destructive ops targeting raw_data, even in exempt download dirs.
    if tokens & DESTRUCTIVE_VERBS:
        return True
    write_attempt = bool(tokens & WRITE_VERBS) or ">" in command
    if not write_attempt:
        return False
    # Writes are allowed only if every raw_data/ reference is inside an exempt subfolder
    # (checked on resolved paths too, so "part50/../x" cannot escape)...
    if NON_EXEMPT_RE.search(cmd_lower):
        return True
    for t in PATH_TOKEN_RE.findall(command):
        if "raw_data/" in t.replace("\\", "/").lower():
            resolved = _to_os_path(t, cwd).replace("\\", "/").lower() + "/"
            if not _is_exempt(resolved):
                return True
    # ...and nothing already there would be overwritten.
    if tokens & ARCHIVE_VERBS and tokens & OVERWRITE_FLAGS:
        return True
    return _overwrites_existing(command, cwd)


def check_path(path: str) -> bool:
    """Return True (block) if path is inside raw_data/ and not a new file in an exempt dir."""
    normalized = os.path.normpath(path).replace("\\", "/").lower()
    in_raw = "/raw_data/" in normalized or normalized.endswith("/raw_data")
    if not in_raw:
        return False
    if not _is_exempt(normalized):
        return True
    return os.path.exists(path)


def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    tool = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})
    cwd = hook_input.get("cwd") or os.getcwd()

    blocked = False

    if tool in ("Bash", "PowerShell"):
        command = tool_input.get("command", "")
        if check_command(command, cwd):
            blocked = True
            print(
                f"\n[BLOCKED] raw_data/ is strictly read-only (new downloads into "
                f"{', '.join(EXEMPT_DIRS)} only; no overwrite/delete/move).\n"
                f"Command attempted: {command[:200]}\n"
                f"All pipeline outputs must go to clean_data/.",
                file=sys.stderr
            )

    elif tool in ("Write", "Edit"):
        path = tool_input.get("file_path", "")
        if check_path(path):
            blocked = True
            print(
                f"\n[BLOCKED] raw_data/ is strictly read-only (new files in exempt "
                f"download dirs only; existing files cannot be changed).\n"
                f"Attempted to write: {path}\n"
                f"All pipeline outputs must go to clean_data/.",
                file=sys.stderr
            )

    sys.exit(2 if blocked else 0)


if __name__ == "__main__":
    main()
