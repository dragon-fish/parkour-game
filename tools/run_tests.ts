#!/usr/bin/env bun
/**
 * Runs the headless test suite through GUT (addons/gut, MIT).
 *
 *   bun tools/run_tests.ts                every test
 *   bun tools/run_tests.ts slide          only files whose name contains "slide"
 *   bun tools/run_tests.ts slide crouch   either of them
 *
 * Filtering matters day to day: the suite spends most of its time awaiting
 * physics frames, so narrowing to the area under change turns minutes into
 * seconds. Unfiltered runs are for CI and for a pre-release check.
 *
 * One script for every platform, replacing the .sh/.ps1 pair that had to be
 * kept in step by hand -- the only thing that actually differed between them
 * was the engine's filename, which is now looked up.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = join(import.meta.dir, "..");
const ENGINE = join(ROOT, ".engine");

/**
 * The engine binary for this platform, inside .engine/.
 *
 * Windows takes the _console build on purpose: the plain one detaches from
 * the terminal and the suite's output goes nowhere. macOS needs no such
 * variant -- the binary inside the .app bundle writes to stdout directly.
 */
function findGodot(): string | null {
  if (!existsSync(ENGINE)) return null;
  const entries = readdirSync(ENGINE);
  if (process.platform === "win32") {
    const consoleBuild = entries.find((e) => e.endsWith("_console.exe"));
    const plain = entries.find((e) => e.endsWith(".exe"));
    const name = consoleBuild ?? plain;
    return name ? join(ENGINE, name) : null;
  }
  if (process.platform === "darwin") {
    const app = entries.find((e) => e.endsWith(".app"));
    if (!app) return null;
    return join(ENGINE, app, "Contents", "MacOS", "Godot");
  }
  const linux = entries.find((e) => e.includes("linux") || e.endsWith(".x86_64"));
  return linux ? join(ENGINE, linux) : null;
}

const godot = findGodot();
if (godot === null || !existsSync(godot)) {
  console.error(`run_tests: no Godot binary in ${ENGINE} -- is .engine/ populated?`);
  process.exit(1);
}

/**
 * Every class_name declared under `dir`, recursively.
 *
 * assets/ and .private/ are not walked: the first is tens of MB of binary the
 * engine checks for itself, the second is a symlink into another repo.
 */
function declaredClasses(dir: string, found: Set<string>): Set<string> {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      declaredClasses(full, found);
    } else if (entry.name.endsWith(".gd")) {
      const match = readFileSync(full, "utf8").match(/^class_name\s+(\w+)/m);
      if (match) found.add(match[1]);
    }
  }
  return found;
}

// Refresh .godot/global_script_class_cache.cfg. Without this, any class_name
// declared since the last editor scan fails to resolve and every test dies
// with 'Identifier "Xxx" not declared in the current scope'.
//
// ⚠️ SKIPPED WHEN THE SET OF class_name DECLARATIONS IS UNCHANGED, because it
// costs ~22 s and a full run of the suite costs ~35 s. What the cache holds is
// exactly that set, so editing a function body cannot invalidate it -- and
// editing function bodies is what a development loop does. Keying on file
// mtimes instead was tried first and is nearly worthless here: every iteration
// touches some .gd, so every iteration paid the 22 s.
//
// The comparison is one-directional and errs toward re-importing: a name in
// either set and not the other triggers it. RUN_TESTS_IMPORT=1 forces it,
// which is also the answer for a NEW BINARY ASSET (a .glb dropped into
// assets/) -- that needs an import and declares no class to notice it by.
const CLASS_CACHE = join(ROOT, ".godot", "global_script_class_cache.cfg");
let cachedClasses = new Set<string>();
if (existsSync(CLASS_CACHE)) {
  const text = readFileSync(CLASS_CACHE, "utf8");
  for (const hit of text.matchAll(/"class":\s*&"(\w+)"/g)) cachedClasses.add(hit[1]);
}
const liveClasses = new Set<string>();
for (const dir of ["scripts", "tests", "tools", "addons"]) {
  if (existsSync(join(ROOT, dir))) declaredClasses(join(ROOT, dir), liveClasses);
}
const drifted = cachedClasses.size !== liveClasses.size
  || [...liveClasses].some((name) => !cachedClasses.has(name));
if (process.env.RUN_TESTS_IMPORT === "1" || cachedClasses.size === 0 || drifted) {
  spawnSync(godot, ["--headless", "--path", ROOT, "--import"], { stdio: "ignore" });
}

// GUT also reads res://.gutconfig.json, which this project uses for exactly one
// setting: failure_error_types drops "engine", so a C++-level engine error no
// longer fails whichever test happened to be running when it fired.
//
// ⚠️ THAT WAS A REAL, LONG-RUNNING FLAKE, and the reason it was so hard to place:
// GUT attributes an engine error to the CURRENT test, so the failure lands on an
// innocent case and moves around between runs. The one behind it here is Jolt's
// "job system exceeded the maximum number of jobs. This should not happen.
// Please report this." -- load-dependent, unrelated to whatever is under test,
// and it picked test_menu one day and test_clip_offsets the next.
//
// push_error and gut errors STILL fail. That is the half worth keeping: the
// grounded-declaration invariant in move_manager.gd and every other
// push_error() guard in this project reports through it.
const gutArgs = [
  "--headless", "--fixed-fps", "60", "--path", ROOT,
  "-s", "res://addons/gut/gut_cmdln.gd",
  "-gprefix=test_",
  "-gexit",
];

const filters = process.argv.slice(2);
if (filters.length === 0) {
  // -gdir without -ginclude_subdirs, so tests/legacy/ stays archived.
  gutArgs.push("-gdir=res://tests");
} else {
  // -gselect takes a single filename substring, so several filters are
  // resolved to explicit paths here instead; -gtest accepts a list. Not
  // recursive, for the same reason -gdir is not.
  const names = readdirSync(join(ROOT, "tests"))
    .filter((name) => name.startsWith("test_") && name.endsWith(".gd"))
    .filter((name) => filters.some((needle) => name.includes(needle)))
    .sort();
  const unique = [...new Set(names)];
  if (unique.length === 0) {
    console.error(`run_tests: no test file matched: ${filters.join(", ")}`);
    process.exit(1);
  }
  console.log(`run_tests: ${unique.length} file(s) matching ${filters.join(", ")}`);
  for (const name of unique) gutArgs.push(`-gtest=res://tests/${name}`);
}

const result = spawnSync(godot, gutArgs, { stdio: "inherit" });
process.exit(result.status ?? 1);
