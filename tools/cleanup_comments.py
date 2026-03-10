#!/usr/bin/env python3
"""Simple cleanup script.

Removes simple comment-only lines from .py files under a target directory.
Backs up files with a .bak extension before modifying.

Usage: python3 tools/cleanup_comments.py lib/ai/src --apply
If `--apply` is not given, runs in dry-run mode and prints candidates.
"""
import sys
from pathlib import Path
import re


def process_file(path: Path, apply: bool) -> int:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    out = []
    removed = 0
    for ln in lines:
        if re.match(r"^\s*#(?!\!|@).*$", ln):
            # simple comment-only line, candidate for removal
            removed += 1
            continue
        out.append(ln)

    if removed:
        print(f"{path}: would remove {removed} simple comments")
        if apply:
            bak = path.with_suffix(path.suffix + ".bak")
            bak.write_text(text, encoding="utf-8")
            path.write_text("\n".join(out) + "\n", encoding="utf-8")
            print(f"{path}: applied, backup -> {bak}")

    return removed


def main():
    if len(sys.argv) < 2:
        print("Usage: cleanup_comments.py <target_dir> [--apply]")
        return
    target = Path(sys.argv[1])
    apply = "--apply" in sys.argv
    total = 0
    for p in target.rglob("*.py"):
        total += process_file(p, apply)
    print(f"Total comment-only lines removed (or would remove): {total}")


if __name__ == '__main__':
    main()
