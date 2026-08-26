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

import { existsSync, readdirSync } from "node:fs";
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

// Refresh .godot/global_script_class_cache.cfg first. Without this, any
// class_name declared since the last editor scan fails to resolve and every
// test dies with 'Identifier "Xxx" not declared in the current scope'.
spawnSync(godot, ["--headless", "--path", ROOT, "--import"], { stdio: "ignore" });

// --fixed-fps is the difference between a suite that takes minutes and one
// that takes seconds: "This setting disables real-time synchronization"
// (Godot's own command line docs), so the main loop runs as fast as the CPU
// allows instead of pacing itself against a wall clock. The delta each frame
// sees is unchanged, so every physics measurement reads exactly the same --
// verified against test_turn_deceleration.gd, which went from 56 s to 0.96 s
// with identical results. 60 to match physics_ticks_per_second, so one
// main-loop frame is one physics tick.
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
