#!/usr/bin/env python3
"""
check_except_patterns.py — scan git diff for exception anti-patterns.

Runs as a post-Dev hook in loop.sh. Flags silent-swallow patterns that turn
errors into degraded state (the R31 class of bug: try/except around a batch
loop that appends a stub dict on failure and silently under-counts).

Usage:
    check_except_patterns.py <project_dir> [--since <commit>]

Exit 0 = clean, 1 = violations found (loop.sh injects output into next Dev prompt).
"""
import os
import re
import subprocess
import sys


def get_diff(proj: str, since: str | None) -> str:
    if since:
        try:
            out = subprocess.check_output(
                ["git", "-C", proj, "diff", "--unified=5", f"{since}..HEAD", "--", "*.py"],
                stderr=subprocess.DEVNULL, text=True,
            )
            if out.strip():
                return out
        except subprocess.CalledProcessError:
            pass
    try:
        return subprocess.check_output(
            ["git", "-C", proj, "diff", "--unified=5", "--", "*.py"],
            stderr=subprocess.DEVNULL, text=True,
        )
    except subprocess.CalledProcessError:
        return ""


def parse_added(diff: str):
    """Yield (file, lineno, line) for '+' lines only."""
    cur_file, cur_line = None, 0
    for raw in diff.splitlines():
        if raw.startswith("+++ b/"):
            cur_file = raw[6:]
            continue
        if raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            cur_line = int(m.group(1)) - 1 if m else 0
            continue
        if raw.startswith("+") and not raw.startswith("+++"):
            cur_line += 1
            yield cur_file, cur_line, raw[1:]
        elif not raw.startswith("-"):
            cur_line += 1


SWALLOW = re.compile(r"^\s*(pass|return\s*(None|\[\]|\{\})?|continue)\s*$")
BARE = re.compile(r"^\s*except\s*:\s*$")
CATCH_ALL = re.compile(r"^\s*except\s+(Exception|BaseException)(\s+as\s+\w+)?\s*:\s*$")


def check(added):
    by_file: dict[str, dict[int, str]] = {}
    for f, n, line in added:
        if f and f.endswith(".py"):
            by_file.setdefault(f, {})[n] = line
    violations = []
    for f, lmap in by_file.items():
        for n in sorted(lmap):
            line = lmap[n]
            justified = any(
                "# except-ok:" in lmap.get(k, "")
                for k in range(max(1, n - 3), n + 1)
            )
            if justified:
                continue
            if BARE.match(line):
                violations.append((f, n, "bare_except", line.strip()))
                continue
            if CATCH_ALL.match(line):
                body = next(
                    (lmap[k].strip() for k in range(n + 1, n + 6)
                     if k in lmap and lmap[k].strip()),
                    None,
                )
                if body and SWALLOW.match(body):
                    violations.append(
                        (f, n, "silent_swallow", f"{line.strip()} → {body}")
                    )
    return violations


def main():
    if len(sys.argv) < 2:
        print("usage: check_except_patterns.py <project_dir> [--since <commit>]", file=sys.stderr)
        sys.exit(2)
    proj = sys.argv[1]
    since = None
    if "--since" in sys.argv:
        idx = sys.argv.index("--since")
        if idx + 1 < len(sys.argv) and sys.argv[idx + 1]:
            since = sys.argv[idx + 1]
    if not os.path.isdir(proj):
        print(f"error: {proj} not a directory", file=sys.stderr)
        sys.exit(2)
    diff = get_diff(proj, since)
    if not diff.strip():
        sys.exit(0)
    violations = check(list(parse_added(diff)))
    if not violations:
        sys.exit(0)
    print("❌ Exception anti-patterns detected in this round's diff:")
    print()
    for f, n, kind, detail in violations:
        print(f"  {f}:{n}  [{kind}]")
        print(f"    {detail}")
    print()
    print("Rules (see agent/dev/prompt.md — exception handling section):")
    print("  1. Default = let exceptions propagate. Catch only with a concrete recovery plan.")
    print("  2. `except:` and `except Exception: pass/return None/[]/{}` are banned —")
    print("     they turn loud failures into silent degradation (R31 class of bug).")
    print("  3. To allow a legitimate catch, add `# except-ok: <specific reason>`")
    print("     on the line directly above the `except` keyword. Example:")
    print("       # except-ok: requests raises ConnectionError on DNS; backoff() retries 3x")
    print("       except ConnectionError as e:")
    print()
    print("Fix these before the next round or the same feedback will return.")
    sys.exit(1)


if __name__ == "__main__":
    main()
