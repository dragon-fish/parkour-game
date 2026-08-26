#!/usr/bin/env bun
/**
 * Lend the private submodule's folders to the project, in place.
 *
 * The assets live in `.private/` (a separate, private repository -- see
 * docs/author-notes.md). This puts a link where each one belongs, so Godot's
 * FileSystem dock shows the model under `assets/models/local/` rather than
 * behind a prefix, and every `res://` path in the project stays as authored.
 *
 * THE LINKS ARE NEVER COMMITTED. Git on Windows checks a committed symlink
 * out as a text file holding its target, which loses the asset silently;
 * they are created locally instead and .gitignore keeps them out of the way.
 *
 * WHY TYPESCRIPT AND NOT A SHELL SCRIPT OR PYTHON. A Windows JUNCTION is the
 * only link a normal user may create there, and it is a first-class citizen
 * of this runtime: `symlink(target, path, "junction")` makes one (the type
 * argument is ignored on POSIX, which gets an ordinary symlink), and `lstat`
 * reports it as a symbolic link -- neither of which is true of Python, where
 * a junction has to be shelled out to `mklink /J` and then recognised by a
 * separate `os.path.isjunction`. Output is UTF-8 whatever the console's
 * codepage is, so a Chinese asset path cannot kill the run half-way through.
 *
 * Safe to re-run, and re-running is the point: it PRUNES links whose folder
 * left `.private`, and moves a REAL folder found in a link's place aside to
 * `<name>_<timestamp>` with a warning rather than clobbering it or skipping
 * quietly -- a real folder there means two sources of truth for one path.
 *
 *   bun tools/link_private.ts
 *   bun tools/link_private.ts --install-hooks    # git runs it after pulls
 */

import { lstatSync, existsSync, readdirSync, readlinkSync, renameSync, mkdirSync, rmdirSync, unlinkSync, symlinkSync } from "node:fs";
import { join, dirname, relative, basename } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = join(import.meta.dir, "..");
const PRIVATE = join(ROOT, ".private");
const MANIFEST = join(PRIVATE, "links.txt");
/** Never worth walking when hunting for stale links. */
const SKIP_DIRS = new Set([".git", ".godot", ".private", ".engine", ".import", "node_modules"]);

function isLink(path: string): boolean {
  try {
    // A junction answers true here, unlike Python's os.path.islink().
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
}

/** Delete the link, never what it points at. */
function removeLink(path: string): void {
  try {
    unlinkSync(path);
  } catch {
    // A junction is a directory to the filesystem: rmdir drops the reparse
    // point and leaves the target alone. Never a recursive remove -- that
    // would walk through and take the real assets with it.
    rmdirSync(path);
  }
}

function stamp(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-` +
    `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

/** Links into .private that the manifest no longer asks for, or whose target
 *  is gone. Refuses to descend through a link, which would lead straight back
 *  into .private. */
function prune(wanted: Set<string>): void {
  const walk = (dir: string) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = join(dir, entry.name);
      if (isLink(path)) {
        let target = "";
        try {
          target = readlinkSync(path);
        } catch {
          continue;
        }
        if (!target.includes(".private")) continue; // somebody else's link
        const relativePath = relative(ROOT, path);
        if (wanted.has(relativePath) && existsSync(join(PRIVATE, relativePath))) continue;
        removeLink(path);
        console.log(`link_private: pruned ${relativePath} ` +
          `(${wanted.has(relativePath) ? "gone from .private" : "no longer listed"})`);
        continue;
      }
      if (entry.isDirectory() && !SKIP_DIRS.has(entry.name)) walk(path);
    }
  };
  walk(ROOT);
}

function installHooks(): number {
  const hooks = join(ROOT, "tools", "githooks");
  if (!existsSync(hooks)) {
    console.log(`link_private: ${hooks} is missing`);
    return 1;
  }
  const result = spawnSync("git", ["config", "core.hooksPath", "tools/githooks"], { cwd: ROOT });
  if (result.status !== 0) {
    console.log("link_private: git config failed");
    return 1;
  }
  console.log("link_private: hooks installed (core.hooksPath = tools/githooks)");
  return 0;
}

async function main(): Promise<number> {
  if (process.argv.includes("--install-hooks")) return installHooks();
  if (!existsSync(MANIFEST)) {
    console.log("link_private: no .private/links.txt -- run:");
    console.log("  git submodule update --init");
    return 0;
  }

  const manifest = (await Bun.file(MANIFEST).text())
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"));

  prune(new Set(manifest));

  let done = 0;
  const conflicts: Array<[string, string]> = [];
  for (const path of manifest) {
    const target = join(PRIVATE, path);
    const link = join(ROOT, path);
    if (!existsSync(target)) {
      console.log(`link_private: missing in .private, skipped: ${path}`);
      continue;
    }
    if (!lstatSync(target).isDirectory()) {
      console.log(`link_private: not a directory, skipped: ${path}`);
      continue;
    }
    if (isLink(link)) {
      removeLink(link);
    } else if (existsSync(link)) {
      // A real folder where a link belongs. Keep it, renamed, and say so --
      // deleting someone's work to make room for a link is never right.
      const kept = `${link}_${stamp()}`;
      renameSync(link, kept);
      conflicts.push([path, basename(kept)]);
    }
    mkdirSync(dirname(link), { recursive: true });
    // Relative, so the pair survives the project being moved or renamed.
    // "junction" is what a Windows user may create without administrator
    // rights; POSIX ignores the type and makes an ordinary symlink.
    symlinkSync(relative(dirname(link), target), link, "junction");
    done += 1;
    console.log(`link_private: linked ${path}`);
  }
  console.log(`link_private: ${done} link(s) in place`);

  if (conflicts.length > 0) {
    console.log();
    console.log("link_private: /!\\ A REAL FOLDER WAS IN THE WAY -- moved aside, not deleted:");
    for (const [path, kept] of conflicts) console.log(`    ${path}  ->  ${kept}`);
    console.log("    The link now points at .private. Merge anything you want to keep into it,");
    console.log("    then delete the copy. A folder named local/ or local_* belongs to .private;");
    console.log("    the main repo must never create one -- see docs/author-notes.md.");
  }
  return 0;
}

process.exit(await main());
