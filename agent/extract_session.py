#!/usr/bin/env python3
"""
Extract latest assistant output from Claude Code session jsonl files.

Usage:
    python3 extract_session.py <project_dir> [--lines N] [--session-id UUID]

Finds the most recent session for a project directory, extracts the last N
assistant messages' text content.
"""

import json
import sys
import os
import glob
import argparse
from pathlib import Path


def find_project_hash(project_dir: str) -> str | None:
    """Find the Claude projects hash directory for a given project path."""
    claude_projects = Path.home() / ".claude" / "projects"
    if not claude_projects.exists():
        return None

    # Claude encodes paths by replacing / with -
    # e.g. /Users/henry/Desktop/公司/AI交通部客服 -> -Users-henry-Desktop----AI-----
    # We need to find which directory matches
    abs_path = os.path.abspath(project_dir)

    for d in claude_projects.iterdir():
        if not d.is_dir():
            continue
        # Try to read a session file to check the cwd field
        jsonl_files = sorted(d.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True)
        if jsonl_files:
            try:
                with open(jsonl_files[0], "r") as f:
                    for line in f:
                        obj = json.loads(line.strip())
                        if "cwd" in obj and obj["cwd"]:
                            if os.path.abspath(obj["cwd"]) == abs_path:
                                return str(d)
                            break
            except (json.JSONDecodeError, KeyError):
                continue
    return None


def extract_latest_output(project_hash_dir: str, max_messages: int = 5, session_id: str = None) -> str:
    """Extract the latest assistant messages from the most recent session."""
    project_path = Path(project_hash_dir)

    if session_id:
        jsonl_files = list(project_path.glob(f"{session_id}.jsonl"))
    else:
        jsonl_files = sorted(
            project_path.glob("*.jsonl"),
            key=lambda f: f.stat().st_mtime,
            reverse=True,
        )

    if not jsonl_files:
        return "[No session files found]"

    # Read the most recent session
    target_file = jsonl_files[0]
    messages = []

    with open(target_file, "r") as f:
        for line in f:
            try:
                obj = json.loads(line.strip())
                if obj.get("type") == "assistant" and "message" in obj:
                    msg = obj["message"]
                    text_parts = []
                    for content in msg.get("content", []):
                        if isinstance(content, dict) and content.get("type") == "text":
                            text_parts.append(content["text"])
                    if text_parts:
                        messages.append("\n".join(text_parts))
            except (json.JSONDecodeError, KeyError):
                continue

    if not messages:
        return "[No assistant messages found]"

    # Return last N messages
    recent = messages[-max_messages:]
    output = []
    for i, msg in enumerate(recent, 1):
        # Truncate very long messages
        if len(msg) > 3000:
            msg = msg[:3000] + "\n... [truncated]"
        output.append(f"--- Assistant message {len(messages) - len(recent) + i} ---\n{msg}")

    return "\n\n".join(output)


def extract_memory(project_hash_dir: str) -> str:
    """Extract memory files from the project."""
    memory_dir = Path(project_hash_dir) / "memory"
    if not memory_dir.exists():
        return "[No memory files]"

    memory_index = memory_dir / "MEMORY.md"
    parts = []

    if memory_index.exists():
        parts.append(f"=== MEMORY.md ===\n{memory_index.read_text()}")

    for f in sorted(memory_dir.glob("*.md")):
        if f.name == "MEMORY.md":
            continue
        parts.append(f"=== {f.name} ===\n{f.read_text()}")

    return "\n\n".join(parts) if parts else "[No memory files]"


def main():
    parser = argparse.ArgumentParser(description="Extract Claude Code session output")
    parser.add_argument("project_dir", help="Path to the project directory")
    parser.add_argument("--lines", "-n", type=int, default=5, help="Number of recent assistant messages (default: 5)")
    parser.add_argument("--session-id", "-s", help="Specific session UUID")
    parser.add_argument("--memory", "-m", action="store_true", help="Also extract memory files")
    parser.add_argument("--format", choices=["plain", "prompt"], default="plain", help="Output format")
    args = parser.parse_args()

    project_hash = find_project_hash(args.project_dir)
    if not project_hash:
        print(f"Error: Could not find Claude project for '{args.project_dir}'", file=sys.stderr)
        sys.exit(1)

    output = extract_latest_output(project_hash, args.lines, args.session_id)
    memory = extract_memory(project_hash) if args.memory else ""

    if args.format == "prompt":
        print("## 開發者最新輸出\n")
        print(output)
        if memory:
            print("\n\n## 專案記憶\n")
            print(memory)
    else:
        print(output)
        if memory:
            print("\n\n" + memory)


if __name__ == "__main__":
    main()
