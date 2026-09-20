#!/usr/bin/env bun
/**
 * Extracts Mirror's Edge chapters, several at a time.
 *
 *   bun tools/extract_levels.ts                  every chapter
 *   bun tools/extract_levels.ts sp05 sp07        only those
 *   bun tools/extract_levels.ts --build          extract, then build each
 *   bun tools/extract_levels.ts --jobs 4         four at a time
 *
 * A chapter's extraction is one Python process that never touches another
 * chapter's output, so the only reason they ran one after another was that
 * nothing ran them otherwise: a full pass was half an hour of one core while
 * fifteen sat idle, and is three minutes now.
 *
 * SIX AT A TIME, not one per core. A chapter peaks around 1.2 GB and the Mall
 * half again that; eight at once ran a 32 GB machine out of memory mid-parse.
 *
 * THE BUILD STAYS SERIAL. Every chapter writes the same mesh library, and two
 * builders in it would race over the same files.
 */

import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const ROOT = join(import.meta.dir, "..");
const LEVELS = join(ROOT, ".private/scenes/local_debug_levels/mirrors_edge/levels");
const EXTRACT = join(ROOT, "docs/mirrors-edge-deep-research/tools/level_extract/extract.py");
const DEFAULT_JOBS = 6;

function findGodot(): string | null {
  const engine = join(ROOT, ".engine");
  if (!existsSync(engine)) return null;
  const entries = readdirSync(engine);
  if (process.platform === "win32") {
    const name = entries.find((e) => e.endsWith("_console.exe")) ?? entries.find((e) => e.endsWith(".exe"));
    return name ? join(engine, name) : null;
  }
  if (process.platform === "darwin") {
    const app = entries.find((e) => e.endsWith(".app"));
    return app ? join(engine, app, "Contents", "MacOS", "Godot") : null;
  }
  const name = entries.find((e) => e.startsWith("Godot") && !e.includes("."));
  return name ? join(engine, name) : null;
}

const args = process.argv.slice(2);
const build = args.includes("--build");
const rebuildInteractions = args.includes("--rebuild-interactions");
const jobsFlag = args.indexOf("--jobs");
const jobs = jobsFlag >= 0 ? Math.max(1, Number(args[jobsFlag + 1])) : DEFAULT_JOBS;
const needles = args.filter((a, i) => !a.startsWith("--") && !(jobsFlag >= 0 && i === jobsFlag + 1));

if (!existsSync(LEVELS)) {
  console.error(`no level configs at ${LEVELS} -- the private submodule is not linked`);
  process.exit(1);
}
const configs = readdirSync(LEVELS)
  .filter((f) => f.endsWith(".json"))
  .filter((f) => needles.length === 0 || needles.some((n) => f.includes(n)))
  .sort();
if (configs.length === 0) {
  console.error(`no chapter matches ${needles.join(", ")}`);
  process.exit(1);
}

function extract(config: string): Promise<{ config: string; ms: number; ok: boolean; tail: string }> {
  const started = Date.now();
  return new Promise((resolve) => {
    const child = spawn("uv", ["run", "--no-project", "--python", "3.12", "--with", "lzallright",
      "--with", "numpy", EXTRACT, join(LEVELS, config)], { cwd: ROOT });
    let output = "";
    child.stdout.on("data", (d) => (output += d));
    child.stderr.on("data", (d) => (output += d));
    child.on("close", (code) => {
      const lines = output.trimEnd().split("\n");
      resolve({
        config, ms: Date.now() - started, ok: code === 0,
        tail: code === 0 ? "" : lines.slice(-12).join("\n"),
      });
    });
  });
}

const queue = [...configs];
const results: { config: string; ms: number; ok: boolean; tail: string }[] = [];
const started = Date.now();
console.log(`extracting ${configs.length} chapters, ${jobs} at a time`);

async function worker(): Promise<void> {
  while (queue.length > 0) {
    const config = queue.shift()!;
    const result = await extract(config);
    results.push(result);
    console.log(`  ${result.ok ? "ok  " : "FAIL"} ${config.padEnd(24)} ${(result.ms / 1000).toFixed(1)}s` +
      ` (${results.length}/${configs.length})`);
    if (!result.ok) console.log(result.tail);
  }
}

await Promise.all(Array.from({ length: Math.min(jobs, configs.length) }, worker));
const failed = results.filter((r) => !r.ok);
console.log(`extracted in ${((Date.now() - started) / 1000).toFixed(1)}s` +
  `${failed.length > 0 ? `, ${failed.length} failed` : ""}`);

if (build && failed.length === 0) {
  const godot = findGodot();
  if (godot === null) {
    console.error("no engine in .engine/");
    process.exit(1);
  }
  for (const config of configs) {
    const scene = `res://scenes/local_debug_levels/mirrors_edge/levels/${config}`;
    const extra = rebuildInteractions ? ["--rebuild-interactions"] : [];
    const run = spawnSync(godot, ["--headless", "--path", ROOT, "--script",
      "res://tools/me_level/build_level.gd", "--", scene, ...extra],
      { cwd: ROOT, encoding: "utf8" });
    const errors = (run.stdout ?? "").split("\n").filter((l) => l.startsWith("ERROR"));
    console.log(`  built ${config.padEnd(24)}${errors.length > 0 ? ` ${errors.length} errors` : ""}`);
    for (const line of errors.slice(0, 3)) console.log(`      ${line}`);
  }
}
process.exit(failed.length > 0 ? 1 : 0);
