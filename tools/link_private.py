#!/usr/bin/env python3
"""Lend the private submodule's assets to the project, in place.

The assets live in ``.private/`` (a separate, private repository -- see
docs/author-notes.md). This puts a link where each one belongs, so Godot's
FileSystem dock shows the model under ``assets/models/`` rather than behind
a prefix, and every ``res://`` path in the project stays as authored.

THE LINKS ARE NEVER COMMITTED. Git on Windows checks a committed symlink
out as a text file holding its target, which loses the asset silently; they
are created locally instead and .gitignore keeps them out of the way.

Cross-platform by construction: POSIX gets symlinks, Windows tries a
symlink and falls back to a directory junction, which needs no
administrator rights. DIRECTORIES ONLY, for exactly that reason -- a
single-file symlink on Windows does need the rights, so a loose private
file belongs in a private directory (`local/`) instead of being linked on
its own.

Safe to re-run: it replaces its own links and refuses to touch real files.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRIVATE = ROOT / ".private"
MANIFEST = PRIVATE / "links.txt"


def read_manifest() -> list[str]:
    lines = MANIFEST.read_text(encoding="utf-8").splitlines()
    return [l.strip() for l in lines if l.strip() and not l.startswith("#")]


def make_link(link: Path, target: Path) -> str:
    """Returns what happened, as a word for the report."""
    # Relative, so the pair survives the project being moved or renamed.
    relative = os.path.relpath(target, link.parent)
    try:
        os.symlink(relative, link, target_is_directory=target.is_dir())
        return "linked"
    except OSError:
        if os.name != "nt" or not target.is_dir():
            raise
    # Windows without Developer Mode: a junction takes no privileges, but it
    # only works for directories and only with an absolute target.
    subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(link), str(target)],
        check=True, capture_output=True,
    )
    return "junction"


def main() -> int:
    if not MANIFEST.exists():
        print("link_private: no .private/links.txt -- run:")
        print("  git submodule update --init")
        return 0

    done = 0
    for path in read_manifest():
        target = PRIVATE / path
        link = ROOT / path
        if not target.exists():
            print(f"link_private: missing in .private, skipped: {path}")
            continue
        if not target.is_dir():
            print(f"link_private: not a directory, skipped: {path}")
            continue
        if link.is_symlink() or (os.name == "nt" and link.is_dir()
                                 and os.path.islink(str(link))):
            link.unlink()
        elif link.exists():
            print(f"link_private: a real file is already there, skipped: {path}")
            continue
        link.parent.mkdir(parents=True, exist_ok=True)
        try:
            how = make_link(link, target)
        except (OSError, subprocess.CalledProcessError) as error:
            print(f"link_private: could not link {path}: {error}")
            continue
        done += 1
        print(f"link_private: {how} {path}")
    print(f"link_private: {done} link(s) in place")
    return 0


if __name__ == "__main__":
    sys.exit(main())
