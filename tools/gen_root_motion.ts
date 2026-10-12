// Generates the root-motion tables from the original's first-person animation
// data, extracted into the untracked research folder. Writes TWO files:
//
//   scripts/player/root_motion_tracks.gd   PUBLIC: each sequence's length and,
//       per root-motion sequence, a SUMMARY of at most SUMMARY_POINTS keys.
//   .private/assets/animations/local/me_root_motion.json   PRIVATE: every key
//       of those sequences, as the original stores them (60 Hz).
//
//   bun tools/gen_root_motion.ts <me-re anims dir>
//   e.g. bun tools/gen_root_motion.ts _local/me-re/anims
//
// DO NOT write the dense keys into the public file. A key-per-frame trajectory
// is the animation asset's own data, and the public repository may carry only
// facts about it: its length, where it ends, and the few turning points that
// give its shape. RootMotionClip.from_track() prefers the private file and
// falls back to the summary, so the game and the suite run on either.
//
// What is written is only what the move logic needs: the root bone's
// trajectory in the actor frame the anim started in (forward, right, up cm,
// yaw degrees turning right). Never bone poses: the original's rest pose is
// not this project's, and the model plays its own clips.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const PUBLIC_OUT = join(ROOT, "scripts/player/root_motion_tracks.gd");
const PRIVATE_DIR = "assets/animations/local";
const PRIVATE_NAME = "me_root_motion.json";

// Keys a summary may keep, the two ends included. The ends are always kept,
// so the total displacement and turn are exact; the rest go where the summary
// is furthest from the track, so they land on its extremes and bends.
const SUMMARY_POINTS = 6;
// A summary stops early once no key is further than this from it (cm, or
// degrees for the yaw).
const SUMMARY_TOLERANCE = 1.0;

const dir = process.argv[2];
if (!dir) throw new Error("usage: bun tools/gen_root_motion.ts <me-re anims dir>");
const privateDir = join(ROOT, ".private", PRIVATE_DIR);
if (!existsSync(privateDir)) {
  throw new Error(`${privateDir} is missing: run git submodule update --init`);
}

// The moves whose animation lengths are read: the ledge family.
const MOVES = [
  "TdMove_SpeedVault", "TdMove_AutoStepUp", "TdMove_StepUp", "TdMove_IntoGrab",
  "TdMove_Grab", "TdMove_GrabPullUp", "TdMove_GrabJump", "TdMove_GrabTransfer",
  "TdMove_IntoClimb", "TdMove_Climb", "TdMove_LedgeWalk", "TdMove_Balance",
];

// The sequences played with root motion or root rotation.
const TRACKED = [
  "HangFoldedHeaveUp", "hangfreeheaveuptocrouch", "HangFreeHeaveUp", "HangHeaveUpToCrouch",
  "HangHeaveUp", "HangFreeHeaveOver", "HangHeaveOver",
  "HangCornerOutSideLeft", "HangCornerOutSideRight", "HangFreeCornerOutSideLeft",
  "HangFreeCornerOutSideRight",
  "LadderExitTopRightHand", "LadderExitTopLeftHand", "pipeexittoprighthand", "pipeexittoplefthand",
  "LadderEnterTop", "walkbalancefalloffleft", "walkbalancefalloffright",
  "stepupleftleg48", "stepuprightleg48", "stepupleftleg88", "stepuprightleg88", "stepup144",
  "AirBargeLand", "swing180", "wallrunvertical180turn",
];

const md = readFileSync(join(dir, "moves_to_anims.md"), "utf8");
const lengths = new Map<string, number>();
let inMove = false;
for (const line of md.split("\n")) {
  if (line.startsWith("### ")) {
    inMove = MOVES.includes(line.slice(4).trim());
    continue;
  }
  if (!inMove || !line.startsWith("| ") || line.startsWith("| anim") || line.startsWith("|---")) continue;
  const cells = line.split("|").map((c) => c.trim());
  const name = cells[1].replace(/\s*\*\*.*$/, "");
  const len = parseFloat(cells[7]);
  if (!name || Number.isNaN(len)) continue;
  lengths.set(name.toLowerCase(), len);
}

type Row = [number, number, number, number, number]; // t s, forward, right, up cm, yaw deg
const round = (x: number, places: number) => Math.round(x * 10 ** places) / 10 ** places;

/** The track's keys, the yaw unwrapped so a half turn reads 180 and not -180. */
function denseRows(name: string): { length: number; rows: Row[] } {
  const j = JSON.parse(readFileSync(join(dir, "root_motion", `${name}.json`), "utf8"));
  const a = j.by_anim_set.AS_C1P_Unarmed;
  const samples: { t: number; delta: number[]; roll_pitch_yaw_deg: number[] }[] = a.samples;
  const rows: Row[] = [];
  let yaw = 0;
  let raw = samples[0].roll_pitch_yaw_deg[2];
  samples.forEach((s, i) => {
    let step = s.roll_pitch_yaw_deg[2] - raw;
    if (step > 180) step -= 360;
    if (step < -180) step += 360;
    yaw += step;
    raw = s.roll_pitch_yaw_deg[2];
    const t = i === samples.length - 1 ? a.SequenceLength : s.t;
    rows.push([round(t, 5), round(s.delta[0], 3), round(s.delta[1], 3), round(s.delta[2], 3), round(yaw, 3)]);
  });
  return { length: a.SequenceLength, rows };
}

/** How far the piecewise-linear summary through `kept` is from row `i`. */
function deviation(rows: Row[], kept: number[], i: number): number {
  let k = 0;
  while (kept[k + 1] < i) k++;
  const p = rows[kept[k]];
  const q = rows[kept[k + 1]];
  const w = q[0] > p[0] ? (rows[i][0] - p[0]) / (q[0] - p[0]) : 0;
  let worst = 0;
  for (let c = 1; c < 5; c++) worst = Math.max(worst, Math.abs(p[c] + (q[c] - p[c]) * w - rows[i][c]));
  return worst;
}

/** The ends, then the furthest key, again, until SUMMARY_POINTS or tolerance. */
function summarise(rows: Row[]): { rows: Row[]; error: number } {
  const kept = [0, rows.length - 1];
  for (;;) {
    let worst = 0;
    let at = -1;
    for (let i = 1; i < rows.length - 1; i++) {
      if (kept.includes(i)) continue;
      const d = deviation(rows, kept, i);
      if (d > worst) {
        worst = d;
        at = i;
      }
    }
    if (at < 0 || worst <= SUMMARY_TOLERANCE || kept.length >= SUMMARY_POINTS) {
      return { rows: kept.map((i) => rows[i]), error: worst };
    }
    kept.push(at);
    kept.sort((x, y) => x - y);
  }
}

const fmt = (row: Row) => `[${row.map((x) => x.toString()).join(", ")}]`;
const dense: Record<string, Row[]> = {};
let summaries = "";
let worstError = 0;
for (const name of TRACKED) {
  const key = name.toLowerCase();
  const { length, rows } = denseRows(name);
  lengths.set(key, length);
  dense[key] = rows;
  const summary = summarise(rows);
  worstError = Math.max(worstError, summary.error);
  summaries += `\t&"${key}": [\n\t\t${summary.rows.map(fmt).join(",\n\t\t")}],\n`;
}

let lens = "";
for (const [name, len] of [...lengths.entries()].sort()) lens += `\t&"${name}": ${round(len, 5)},\n`;

const out = `class_name RootMotionTracks
extends RefCounted

# GENERATED by tools/gen_root_motion.ts from the original's first-person
# animation data. DO NOT edit by hand: change the generator and re-run it.
#
# [ME:CONFIRMED anims/moves_to_anims.md, anims/root_motion] LENGTHS are
# SequenceLength at rate 1 of the AS_C1P_Unarmed sequence, keyed by the
# lowercased name (the original's names are case-insensitive).
#
# [ME:DERIVED anims/root_motion] SUMMARIES are, for the sequences a move plays
# with root motion or rotation, at most ${SUMMARY_POINTS} keys of the root bone's track:
# its two ends exactly (so the total displacement and turn are the track's
# own) and the keys where a straight line between those strays furthest from
# it. Each row is [time s, forward cm, right cm, up cm, yaw degrees turning
# right], relative to where the root was at 0 and in the actor frame the
# sequence started in.
#
# DO NOT put the dense track here. Every key of it is the asset's data and
# lives in the private submodule (DENSE_PATH); RootMotionClip.from_track()
# reads that file when it is there and these summaries when it is not, so
# nothing may depend on a key a summary does not keep.

const DENSE_PATH := "res://${PRIVATE_DIR}/${PRIVATE_NAME}"

const LENGTHS := {
${lens}}

const SUMMARIES := {
${summaries}}
`;
writeFileSync(PUBLIC_OUT, out);
writeFileSync(join(privateDir, PRIVATE_NAME), JSON.stringify({ tracks: dense }) + "\n");
console.log(`${lengths.size} lengths, ${TRACKED.length} tracks; ` +
  `summaries stray at most ${round(worstError, 2)} cm/deg from the tracks`);
