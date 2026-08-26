# Level templates

`templates/base_level.tscn` is the base scene for building new whitebox
levels quickly, using Godot's "inherit scene" feature. It is hand-authored
and lives outside the generated-content pipeline — see
[Generated vs. hand-authored](#generated-vs-hand-authored) below before
touching either.

## Creating a new level from the template

1. **Scene > New Inherited Scene**, pick `templates/base_level.tscn`.
2. Save the new scene somewhere under `scenes/` (or wherever your level
   belongs) with its own name.
3. Add your level's geometry, obstacles, and practice areas **in the child
   scene, never in the base**. An inherited scene can only add nodes and
   override properties on existing ones — it cannot delete or reparent nodes
   that came from the base. If you find yourself wanting to remove or
   restructure something from the template, that is a sign it belongs in the
   child instead of being fought in the editor.
4. Don't touch `Sun`, `WorldEnvironment`, `SpawnPoint`, `Floor`, `Player`,
   `DebugHud`, or `TuningPanel` in the child unless you specifically mean to
   override them (e.g. moving `SpawnPoint`, resizing `Floor`). Everything
   else — ramps, walls, gaps, platforms — are new siblings you add under the
   inherited root.
5. Every level built from the template inherits its cold-blue ambient tint
   (`WorldEnvironment`'s `ambient_light_color`, Mirror's Edge-leaning shadows)
   for free; tune how strong it reads with the F1 panel's
   `ambient_cold_strength` dial (Camera tab).

## Fog: how far this level lets you see

The template's `Arena` root carries a `FogConfig` in its `fog` export
(`scripts/level/fog_config.gd`). It drives two unrelated Godot systems, and
each does a job the other cannot:

| Dial | Drives | Job |
| --- | --- | --- |
| `fade_begin_distance` / `fade_end_distance` / `max_opacity` / `tint` / `sky_blend` | `Environment`'s DEPTH fog | Hides an unfinished horizon. Cheap, unlimited range, no interaction with light. |
| `volumetric_enabled` / `volumetric_density` / `volumetric_distance` / `volumetric_ambient_inject` | `Environment`'s VOLUMETRIC fog | Light shafts. Voxelised, reaches only `volumetric_distance` from the camera, and is the only one a light can carve a beam out of or a body can cast a hole in. |

Defaults draw the curtain from 60 m to 160 m — far enough not to crowd a
whitebox, near enough that a rooftop view does not expose ground nobody has
built yet.

**Per level, not per player.** `fog` is a node property, so an inherited scene
overrides it with one click in the Inspector, the same as moving `SpawnPoint`.
Deliberately NOT a `MovementConfig` group: that object follows the player from
level to level, and a fogged rooftop and a clear blue courtyard have to be able
to disagree.

**Turning it off.** Uncheck `enabled` for 晴空万里 — `Arena` switches both fogs
off at the `Environment`, and the values you tuned stay where they are. That is
not the same as clearing the `fog` export entirely: an empty `fog` means "this
level does not manage fog at all", and `Arena` then leaves whatever the scene's
own `Environment` says completely alone. Use the checkbox for a clear day, the
empty export for a hand-authored sky.

**Tuning it.** All four floats are live on the F1 panel's **fog** tab, applied
every frame by `Arena._process()` — the same "consumer re-applies so a drag
takes effect now" pattern `ambient_cold_strength` uses. They are the one page
the panel builds from the LEVEL rather than from `MovementConfig`, which is
also why **Save/Load preset does not touch them**: a feel preset saved on a
fogged rooftop must not re-fog the next level it is loaded into.

### Two dials that look broken until you know about the other one

**`tint` looks grey no matter what you set it to** → check `sky_blend`. It is
Godot's `fog_aerial_perspective`: the fraction of the fog colour handed over to
the real sky behind it. The default `ProceduralSkyMaterial`'s horizon is
(0.646, 0.656, 0.671) — grey — so a high blend turns any tint, white included,
into that grey. It defaults to 0.25, where white still reads white. This was a
hardcoded 0.6 once and the tint dial visibly did not work.

**A `FogVolume` renders nothing** → check `volumetric_enabled`, not the
density. `FogVolume`s only appear when `Environment.volumetric_fog_enabled` is
true, and a global `volumetric_density` of **0 is a legitimate setting**: it is
Godot's documented way to get fog *only* inside `FogVolume`s — dust in a light
shaft, clear air around it. So the switch and the thickness are two fields, and
zeroing the thickness must never be read as "off".

### Keep the two fogs' ranges apart

The depth fog and the volumetric fog are drawn independently and you see through
**both**. A white far curtain that begins at 30 m while the volumetric fog still
reaches 64 m is a white wall viewed through 30 m of dim haze, and it reads grey
no matter what `tint` says — the tint dial is not broken, the ranges overlap.
Keep `volumetric_distance` below `fade_begin_distance` when you want "near
atmosphere, far white". Nothing enforces it; some levels want them mixed.

Shortening `volumetric_distance` also **sharpens light shafts for free**: the
froxel grid is a fixed cell count spread across that distance, so 30 m of fog
carries more than twice the detail of 64 m.

That cell count is `rendering/environment/volumetric_fog/volume_size` and
`…/volume_depth` in `project.godot`, **raised from Godot's 64 to 128**. Godot's
default spreads 64³ froxels over the whole fog range, which is far coarser than
the 4096 shadow map surfaces get — so a scene shows crisp shadows on its walls
and a mushy blob of a light shaft in the air, and an occluder thinner than one
froxel (a roof panel) fails to block sunlit fog above it at all. It is global
and it costs GPU time; halve both numbers to take it back.

> The reason that explanation lives here and not beside the setting: the Godot
> editor strips `;` comments out of `project.godot` whenever it re-saves, and
> it did exactly that to the first copy of this note. Same trap
> `Arena.COLD_AMBIENT_TINT` describes for `.tscn` files.

`volumetric_ambient_inject` is the other half of "why is my fog grey". Volumetric
fog is **lit** fog, not coloured fog: its colour is whatever light reaches each
cell. Godot defaults the ambient contribution to 0, so fog standing in shadow is
not dim white but black — white where a light reaches it, black where it does
not, grey on average. Turn it up for even haze, down for the strongest shafts.
A shaft *is* the contrast between lit and unlit fog, so the two wants are
opposed and this dial is where you pick.

### Fog is per level automatically; the sky is shared on purpose

A resource embedded in a scene file is **one object**, shared by every
instantiation, with a `resource_path` pointing back into that file — so editing
an inherited level's fog in the inspector would edit `base_level.tscn` itself
and move every other level with it. The template's `FogConfig` therefore sets
`resource_local_to_scene = true`: each level takes its own copy at
instantiation, nobody has to remember to right-click > **Make Unique**, and an
F1 drag in one level cannot reach another. `tools/arena_builder.gd` sets the
same flag on the copy it builds. `tests/test_level_fog.gd` guards it, because
dropping the flag breaks nothing visible until two levels are open.

The **sky** goes the other way deliberately: it is one shared
`assets/sky/day_sky.tres` that every scene loads by path, so changing the
game's weather is one field in one file. A level that wants its own assigns a
different `Sky` resource rather than uniquifying the shared one — see
[assets/sky/README.md](../assets/sky/README.md).

### The editor viewport shows no fog, on purpose

Fog is **not** baked into either scene's `Environment` resource — not
`templates/base_level.tscn`'s and not the one `tools/arena_builder.gd` builds.
`Arena` writes it at runtime and only at runtime. Two reasons, and don't
"fix" this:

- The Godot 3D viewport renders the edited scene's `WorldEnvironment`. Bake
  the fog in and you spend every level-building session unable to see your own
  geometry past 60 m.
- A copy in the `.tscn` would be a second source of truth for numbers the
  `FogConfig` already holds, and the two would drift — the exact problem
  `Arena.COLD_AMBIENT_TINT`'s comment describes for the ambient colour, which
  really does live in four places and really does have to be kept in step.

Press play to see the fog. F1 to tune it.

## Traps

### `TuningPanel` is found by name, not by type or export

`arena.gd`'s `_ready()` locates the panel with:

```gdscript
var panel := get_node_or_null("TuningPanel")
if panel != null:
    panel.config = config
```

This is a plain string lookup, not an `@export`. If a node named
`TuningPanel` doesn't exist under the arena root with that *exact* name and
casing, `get_node_or_null` silently returns `null`, the `if` is skipped, and
the panel — if one exists elsewhere in the tree — never receives a
`MovementConfig`. The F1 tuning UI then either doesn't build (its `config` is
still null when `_build_ui()` runs) or, if it did build against a leftover
value, edits an object nothing else reads. Either way, live tuning quietly
stops working and nothing tells you — the sliders still render.

Renaming or deleting `TuningPanel` in an inherited scene is exactly the kind
of "harmless-looking" edit this describes. Don't.

### `Arena.player` and `Arena.spawn_point` are required, not optional

`arena.gd` unconditionally dereferences both in `_ready()`
(`player.setup(...)`, `spawn_point.global_position`). If the node named
`Player` or `SpawnPoint` is renamed, moved to a different parent, or
otherwise stops matching the `NodePath` baked into the template's
`@export var player: Player` / `@export var spawn_point: Marker3D`, the
export resolves to `null` and `_ready()` throws a null-reference error the
moment the level loads — not a graceful failure, a crash that takes the
whole level down. Because every inherited level shares this one base scene,
a mistake here breaks every level built from the template at once, not just
the one you were editing.

### `MovementConfig.fall_recovery_depth` and floating platforms

`Arena._physics_process()` teleports the player back to `SpawnPoint` once
they fall more than `config.fall_recovery_depth` (default `20.0`) below the
floor. This is the safety net for missed jumps — but it means **any drop the
player can fall into that is deeper than `fall_recovery_depth` looks the same
as falling off the level entirely**: they get yanked back to spawn instead of
continuing to fall or landing on whatever's below.

This matters most for levels built from floating platforms with no
continuous ground underneath: a platform-to-platform layout can have "gaps"
deeper than 20m between the play surface and whatever's below (or nothing
below at all), and a player who overshoots a jump there respawns instead of
falling to their death or into some other trap — which may or may not be
what you intended. If you want a genuine bottomless pit or a different
recovery behavior, design around this value (it's tunable per-arena via the
`config` export, and live via the F1 panel) rather than assuming "falling
off" always means "off the whole level."

### Generated vs. hand-authored

`scenes/main.tscn` and `templates/base_level.tscn` look similar (both are
`Arena`-rooted scenes with the same core nodes) but are produced by opposite
workflows, and mixing them up corrupts one or the other:

- **`scenes/main.tscn` is generator output.** It's built by
  `ArenaBuilder.build()` (`tools/arena_builder.gd`) and written by
  `tools/build_main_scene.gd`. `tests/test_arena.gd`'s
  `test_regenerating_the_scene_matches_what_is_committed` regenerates it in
  memory on every test run and asserts it matches the committed file
  node-for-node. **Never hand-edit it** — the practice-course geometry
  (`JumpArea`, `SlideArea`, `VaultArea`, `WallArea`, ...) is defined once in
  `arena_builder.gd`, and a hand edit to the `.tscn` will be silently
  overwritten the next time someone runs the generator, or will fail that
  test if it survives until the next CI run.
- **`templates/base_level.tscn` (and anything inherited from it) is
  hand-authored.** There is no generator for it and none should be added —
  it exists specifically so a person can build a level in the editor. Don't
  try to make `arena_builder.gd` or a similar script produce or regenerate
  it.

If you're not sure which category a scene under `scenes/` or `templates/`
falls into, check whether a `tools/build_*.gd` script writes to that path;
if one does, treat the `.tscn` as read-only and edit the generator instead.

## Regression coverage

`tests/legacy/test_base_level_template.gd` loads and instantiates
`templates/base_level.tscn` directly and checks the things every inherited
level silently depends on: the root carries `arena.gd` and its `player` /
`spawn_point` exports resolve, the player and `TuningPanel` share one
`MovementConfig` instance, `DebugHud.player` resolves, and — the most
end-to-end check — a player dropped into the template actually settles onto
the floor and ends up in the `Ground` state, rather than merely having the
right node names. Run it (along with everything else) via
`bun tools/run_tests.ts`.

## Placing a zipline (or any interest line)

1. Add Node → `InterestLine` (it is a `Path3D`; the class is registered from
   `scripts/level/interest_line.gd`).
2. In the 3D viewport, use the Path3D toolbar to click the control points:
   two for a straight cable, three with the middle one dragged down for a
   sagging one. Points are local to the node, so moving the node moves the
   whole cable.
3. In the inspector leave `kind = ZIPLINE` and `reach_radius = 0.6` unless
   you mean otherwise.
   Set kind = SWING instead and the same node is a swing bar (hang below,
   swing perpendicular to the line).

The collision volume is built along the curve at runtime; do not add one by
hand. The cable has no mesh yet — F12 draws it in play.

## Placing a ladder

A ladder (or a vertical pipe — same mechanic, see the design spec's
"水管和梯子性质相同" ruling) is the same `InterestLine` node as a zipline,
just drawn and aimed differently.

1. Add Node → `InterestLine`, same as any interest line.
2. Draw the curve **vertically**: the bottom control point at the foot of the
   ladder, the top one at the top rung. The curve is the climb's own centre
   line, not an offset — `LadderConfig.stand_off` (0.4 m) is what keeps the
   capsule's centre off the wall the ladder is mounted to, so the curve
   itself should hug the rungs.
3. Set `kind = LADDER`.
4. Aim the node's **-Z toward the side the player stands on** to climb it —
   the same facing convention `Checkpoint` uses. Ladders have an authored
   front: entry only works from that half-space (grounded, airborne, and
   wallrunning bodies alike), and a body passing the volume from the back
   is not caught. "Align Rotation with View" from where the player would
   stand, facing the ladder, places this correctly.
5. The BOTTOM end may be sunk into the surrounding geometry (a rung buried
   in the floor slab) without causing a bug — the steady climb is
   collision-checked (`slide_to()`), so the body stops at the real floor
   rather than clipping through it or overshooting past a line end left a
   little generous. Only the brief magnet fade-in on first catch is a raw
   position write; see `ladder_move.gd`'s own header note for why. The TOP
   end does NOT get the same slack: the top-exit deck probe (Task 7) fires
   from the line's own top point and only reaches ±0.5 m above/below it
   (`LadderMove.TOP_DECK_PROBE_LIFT`/`TOP_DECK_PROBE_DEPTH`) — keep the top
   point within about 0.5 m of the deck surface it should exit onto, or W at
   the top will find nothing to stand on.

The collision volume is built along the curve at runtime, same as any other
interest line — do not add one by hand.

## Placing a checkpoint

1. Add Node → `Checkpoint` (an `Area3D`; the class comes from
   `scripts/level/checkpoint.gd`).
2. Give it any `CollisionShape3D` children — the trigger is whatever shape
   you build, and walking into it saves the respawn.
3. Aim the node: the player wakes up with their BODY CENTRE at its origin
   (the same convention as SpawnPoint), facing its -Z -- so place the node
   about 1 m above the floor. The gizmo shows exactly where the capsule
   lands, and the node keeps itself level (yaw only), so "Align Transform
   with View" from any camera angle just works; drag the arrow-tip handle
   to turn the facing.
4. `display_name` makes the save announce itself -- 「检查点 <名字> 已保存」
   -- shown only when the active respawn actually changes. Leave it empty
   for a silent checkpoint.

Deaths and a TAP of R both respawn at the last touched checkpoint; with none
touched yet, the level's own `SpawnPoint` is used. HOLDING R for a second
before release forgets the checkpoint and returns to the SpawnPoint (debug).
The SpawnPoint wears the same preview in purple -- note its capsule hangs
BELOW the marker: spawn markers were always placed at the body's centre
height, and existing levels keep that convention.
