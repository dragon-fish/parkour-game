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

`tests/test_base_level_template.gd` loads and instantiates
`templates/base_level.tscn` directly and checks the things every inherited
level silently depends on: the root carries `arena.gd` and its `player` /
`spawn_point` exports resolve, the player and `TuningPanel` share one
`MovementConfig` instance, `DebugHud.player` resolves, and — the most
end-to-end check — a player dropped into the template actually settles onto
the floor and ends up in the `Ground` state, rather than merely having the
right node names. Run it (along with everything else) via
`pwsh tools/run_tests.ps1`.

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
