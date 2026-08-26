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

Safe to re-run, and re-running is the point: it also PRUNES links whose
folder no longer exists in .private (a folder deleted upstream leaves a
dangling link that Godot reports as a missing resource), and it moves a
REAL directory found in a link's place aside to `<name>_<timestamp>` rather
than either clobbering it or silently skipping it -- a real folder there
means two sources of truth for the same path, and staying quiet about it is
how the wrong one wins.

Run it from a git hook to keep the links in step with checkouts and pulls:

    git config core.hooksPath tools/githooks

or `python3 tools/link_private.py --install-hooks`, which does that for you.
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRIVATE = ROOT / ".private"
MANIFEST = PRIVATE / "links.txt"


## Directories never worth walking when hunting for stale links.
SKIP_DIRS = {".git", ".godot", ".private", ".engine", ".import", "node_modules"}


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


def prune(wanted: set[Path]) -> int:
    """Removes links into .private that the manifest no longer asks for, or
    whose target is gone. Symlinked directories are listed but never walked
    into (os.walk does not follow them by default), so this stays cheap."""
    removed = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in list(dirnames) + filenames:
            path = Path(dirpath) / name
            if not path.is_symlink():
                continue
            target = os.readlink(path)
            if ".private" not in target:
                continue  # somebody else's link, not ours to manage
            if path in wanted and (PRIVATE / path.relative_to(ROOT)).exists():
                continue
            path.unlink()
            removed += 1
            print(f"link_private: pruned {path.relative_to(ROOT)} "
                  f"({'no longer listed' if path not in wanted else 'gone from .private'})")
    return removed


def move_aside(path: Path) -> Path:
    """A real folder sitting where a link belongs. Keep it, renamed, and say
    so -- deleting someone's work to make room for a link is never right."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    kept = path.with_name(f"{path.name}_{stamp}")
    path.rename(kept)
    return kept


def install_hooks() -> int:
    hooks = ROOT / "tools" / "githooks"
    if not hooks.is_dir():
        print(f"link_private: {hooks} is missing")
        return 1
    subprocess.run(["git", "config", "core.hooksPath", "tools/githooks"],
                   cwd=ROOT, check=True)
    print("link_private: hooks installed (core.hooksPath = tools/githooks)")
    return 0


def main() -> int:
    if "--install-hooks" in sys.argv:
        return install_hooks()
    if not MANIFEST.exists():
        print("link_private: no .private/links.txt -- run:")
        print("  git submodule update --init")
        return 0

    manifest = read_manifest()
    prune({ROOT / p for p in manifest})

    done = 0
    conflicts = []
    for path in manifest:
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
            kept = move_aside(link)
            conflicts.append((path, kept.name))
        link.parent.mkdir(parents=True, exist_ok=True)
        try:
            how = make_link(link, target)
        except (OSError, subprocess.CalledProcessError) as error:
            print(f"link_private: could not link {path}: {error}")
            continue
        done += 1
        print(f"link_private: {how} {path}")
    print(f"link_private: {done} link(s) in place")
    if conflicts:
        print()
        print("link_private: ⚠️  A REAL FOLDER WAS IN THE WAY -- moved aside, "
              "not deleted:")
        for path, kept in conflicts:
            print(f"    {path}  ->  {kept}")
        print("    The link now points at .private. Merge anything you want "
              "to keep into it,")
        print("    then delete the copy. A folder named local/ or local_* "
              "belongs to .private;")
        print("    the main repo must never create one -- see "
              "docs/author-notes.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
