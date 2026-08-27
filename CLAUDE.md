# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A parkour prototype in **Godot 4.7**, rebuilt against *measurements of Mirror's
Edge (2008)* rather than against remembered feel. The movement code is ordinary;
the **provenance of every number** is the point.

**First person is the default view, not the only one.** A full third-person
camera exists (`V`, and `CameraRig` treats it as a saved viewing preference, with
wheel zoom, shoulder cycling and a collision probe). Both views share **one**
movement stack and **one** animation set — there is no third-person branch in the
moves. What differs is the camera: several offsets in `CameraConfig` were tuned
against the first-person eye, so a change that improves third-person framing may
be paying for it in first person. Check both before calling a camera change done.

## Commands

The engine binary is untracked and lives in `.engine/` (on macOS, inside the
`.app` bundle: `.engine/Godot_*.app/Contents/MacOS/Godot`).

**Use that binary, never whatever `godot` is on PATH.** `.engine/` exists to pin
the engine version: Godot's 4.x line ships breaking changes at a rate that makes
"whichever 4.x is installed" a real source of silent drift. This project stays on
**4.7**; upgrading is a deliberate decision to take separately, not something to
do in passing because a newer build happened to be handy.

```sh
# Tests — ALWAYS use this, not a raw gut_cmdln invocation. It refreshes the
# global script class cache first (without it every test dies on
# 'Identifier "Xxx" not declared') and runs with --fixed-fps 60, which is the
# difference between minutes and seconds.
bun tools/run_tests.ts                 # whole suite
bun tools/run_tests.ts slide crouch    # only tests/test_*<needle>*.gd

# Private assets (models, paid animation packs) — see docs/author-notes.md
git submodule update --init
bun tools/link_private.ts --install-hooks   # once per machine; also builds the links

# Play
<engine> --path . res://scenes/ui/main_menu.tscn

# Referential integrity: catches a .tres that silently lost an ext_resource
<engine> --headless --script res://tools/check_references.gd

# Screenshot a scene without hijacking the desktop (note: NO --headless)
<engine> --path . --resolution 960x540 --quit-after 300 \
    --script res://tools/capture.gd -- <scene_path> <output_png> [settle_frames]
```

`tests/legacy/` is archived and deliberately outside the run.

## Architecture

### Movement: Player owns data, moves own transitions

- `scripts/player/player.gd` (`Player`, `CharacterBody3D`) holds the shared
  state and the movement *primitives* (accelerate, step-up, capsule resize,
  timers, body/animation mounting). It contains **no transition logic**.
- `scripts/player/moves/*_move.gd` each own one action. Every "can I go from X
  to Y" has exactly one answer and it lives in **X's** `physics_update`, which
  returns the next move's name or `Move.KEEP`.
- Move name constants live on `Move`, not on `Player`. GDScript resolves
  `class_name` globals at parse time, so `Player -> moves -> Move` must stay
  one-directional; `Move.player` is untyped for the same reason.
- `MoveManager` registers instances, runs the active one, and owns
  `redo_move_time` cooldowns. It also enforces the **grounded-declaration
  invariant**: `Player.grounded` is *declared* by the active state, never
  inferred from `is_on_floor()` (scripted moves never call `move_and_slide()`).
  A state that forgets gets a `push_error`.
- Cross-move data travels on one-shot fields on `Player` (`pending_vault_variant`,
  `pending_ledge`, …) — the manager has no other channel. The reader clears them.

### Config: one aggregate, one resource per move

`MovementConfig` (`scripts/player/movement_config.gd`) is an aggregate root that
holds nothing itself. It composes `PawnConfig` (Pawn-wide, mirrors the original's
`TdPawn` CDO), `CameraConfig`, and one `MoveConfig` subclass per move under
`scripts/player/config/moves/`. `Arena` owns the single instance and injects it
into Player / CameraRig / Probes / TuningPanel, so a preset is one `.tres`.

`MoveConfig` defaults are **deliberately neutral** — declaring a value is how a
move opts into being different. Per-move behaviour switches (`check_for_grab`,
`allows_turn`, `freeze_visual_yaw`, look constraints) are data on the config, not
branches in the state.

### Supporting systems

| Path | Role |
|---|---|
| `scripts/player/probes.gd` | All environment queries. Converts feet-relative config heights to world Y so states never think about the capsule origin. |
| `scripts/camera/camera_rig.gd` | Everything the camera does beyond sitting on the head, first and third person both. Fed *values* (speed, grounded, wall side, head offset), never scene references. Owns no movement logic. `_apply_body_layers()` is what swaps the body's first/third-person render layers — see `headless_variant.gd` for how that split is built. |
| `scripts/player/character_animator.gd` | Reads movement state, puts a clip on screen. Every mapping is a **priority list**, because `body_scene` is optional and no clip may be assumed to exist. |
| `scripts/player/body_profile.gd` + `body_tuning.gd` | A body is described by one `BodyProfile` resource. The *binding* (which .vrm/.glb) is machine-local and untracked; the *tuning* (mount offsets, clip offsets/timings) is tracked as JSON in `scenes/player/tuning/`, keyed by model filename with `default.json` as fallback. |
| `scripts/player/input/` | `InputSource` seam: `KeyboardInputSource` reads physical keycodes (no InputMap actions exist); `ScriptedInputSource` is what tests drive. |
| `scripts/level/arena.gd` | Owns the config instance, respawn, checkpoints, fog. `DeathSequence` is a level concern, not a Move. |
| `scripts/ui/` | UI is **built in code**, not laid out in `.tscn` (`pause_ui.gd` is an autoload, so every level including debug whiteboxes gets pause for free). |

### Generated vs. hand-authored scenes

`scenes/main.tscn`, `scenes/player/player.tscn` and
`scenes/generated/calibration_course.tscn` are **generated** by `tools/build_*.gd`
from `tools/arena_builder.gd` / `player_builder.gd`. For the first two,
`tests/test_generated_scenes.gd` re-runs the builder in memory and compares
node-by-node against the committed file — change a builder without re-running its
script and the suite fails. (It compares in memory on purpose: re-running the
generator would repair the drift as a side effect of measuring it.) `templates/base_level.tscn` is hand-authored and outside that
pipeline (see `docs/level-templates.md`).

## Conventions that bite

- **Code comments in English**, and they carry provenance: ✅ = confirmed by
  measurement of the original, ⚠️ = inferred. Changing a value means changing the
  reasoning above it. A change that improves feel but contradicts a measurement
  must say so out loud rather than quietly overwrite it.
- **A comment exists so a mistake is not repeated, not so the history can be
  read** — see CONTRIBUTING.md for the full rule. Constraints, potholes and what
  they cost, prohibitions; no quoted conversations, no dates, no before/after.
  Rewrite a comment when the logic changes instead of appending to it: it should
  read as though written in one sitting. The ✅/⚠️ measurement provenance is a
  *constraint*, not a quotation — "gravity is 16.0, 22 measured jumps pin it,
  the ini's 800 is wrong, do not put it back" — and stays. Lessons learned go to
  `.claude/skills/`, derivations to `docs/`, history to git.
- **`docs/feel-backlog.md`** is the standing record of known-wrong feel with root
  causes already derived. Read it before "fixing" a movement value.
- **`.claude/skills/`** holds practices this project learned the hard way — each
  exists because ignoring it cost a session. Consult the matching one *before*
  hand-editing `.tscn`/`.tres`/`.import`, syncing assets, building UI from code,
  verifying visuals headlessly, adding a rule where a dial belongs, or naming
  config fields.
- **Never create a folder named `local` or `local_*`** in this repo. Those names
  belong to the `.private` submodule and are symlinked into place by
  `tools/link_private.ts`; `.gitignore` enforces it.
- **The editor strips `;` comments from `.tscn` on re-save** — warnings about a
  scene's values live in the code that drives them (see `Arena.COLD_AMBIENT_TINT`).
- **Tuning values do not get unit tests.** Structural invariants do. See
  `.claude/skills/tuning-dials-not-rules`.
- Commit messages: Conventional Commits, English.
- No character models or paid animation packs in this repo — `Player.body_scene`
  is an optional runtime mount point and the whole suite passes with nothing
  attached.

## Reference docs

`docs/mirrors-edge-deep-research/` is the measurement corpus every ✅ cites
(`02-速度系统`, `05-动作库总览`, `06-Move状态机架构`, `09-Godot移植指南`, …).
Cross-cutting principles: `docs/camera-authority.md` (who moves the body decides
whether the camera lags), `docs/contact-drives-movement.md` (a direction change
means a hand or foot touched something), `docs/capsule-leads-presentation.md`
(the capsule's path is simple; camera and animation follow it),
`docs/seamless-loading.md` (no frame may exceed budget while the player cannot
act). Specs and plans live under `docs/superpowers/`.
