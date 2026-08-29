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

### Volumetric fog is OFF by default, and should stay that way

"Clear nearby, thickening in the distance" is the **depth** fog, and its
defaults already are exactly that — 60 m to 160 m. Reach for
`volumetric_enabled` only when a level wants **light shafts**, because that is
the only thing volumetric fog can do that the depth fog cannot.

It defaults off because it shipped on and should not have: volumetric fog fills
the air *everywhere* inside `volumetric_distance`, including the metre in front
of the player's face, so every level came out of the box wearing a uniform haze
it had no use for. Without a strong light and something to occlude it, that
haze is not atmosphere — it is soup. A light shaft is something a level asks
for, not a tax every level pays.

`scenes/debug_levels/factory_hall.tscn` is the level that does ask, and it says
so explicitly.

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
4. `tag` is optional and only matters if a `ModifierVolume` is going to
   forbid this particular line — `BLOCK_INTEREST_LINE` addresses a line **by
   name**. An untagged line has no name to address and so can never be
   singled out; it is still caught by a blanket ban on its whole kind
   (`BLOCK_ZIPLINE`, `BLOCK_SWING`, `BLOCK_LADDER`). Blocking one rope does
   not block rope: `tag = &"pipe_a"` under a `BLOCK_INTEREST_LINE` volume
   takes that one cable out of play and leaves every other zipline in the
   level catchable.

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

## Placing a modifier volume

A `ModifierVolume` is how a level says "not here": a region that puts
temporary, time-limited modifications on whoever walks in — a ground speed
ceiling, a forbidden move, a forbidden named interest line, a forced camera
view, a stumble. It is the only author-facing surface of the status layer.

1. Add Node → `ModifierVolume` (an `Area3D`; the class comes from
   `scripts/level/modifier_volume.gd`).
2. Give it any `CollisionShape3D` children — like `Checkpoint`, the trigger
   is whatever shape you build, of however many parts. A corridor can be
   three boxes under one node.
3. Fill in `apply` with one `StatusSpec` row per modification. Each row is
   an `effect`, a `seconds`, and whichever payload field that effect reads.
4. Optionally fill in `remove` to lift something on the way in. Only
   `effect` and `subject` are read there; `amount`, `view` and `seconds` are
   ignored. An empty `subject` lifts every subject of that effect.

### The effect vocabulary

| effect | reads | means |
|---|---|---|
| `SPEED_CAP` | `amount` | multiplies the ground speed ceiling (0..1) |
| `FORCE_VIEW` | `view` | renders in `FIRST` or `THIRD` whatever the player's saved preference is, and leaves that preference untouched |
| `BLOCK_INTEREST_LINE` | `subject` | forbids the one line whose `tag` matches |
| `BLOCK_JUMP`, `BLOCK_SLIDE`, `BLOCK_SKILL_ROLL`, `BLOCK_COIL`, `BLOCK_WALL_RUN`, `BLOCK_WALL_CLIMB`, `BLOCK_GRAB`, `BLOCK_SPEED_VAULT`, `BLOCK_LADDER`, `BLOCK_ZIPLINE`, `BLOCK_SWING`, `BLOCK_TURN_180` | nothing | forbids that move |
| `STAGGER` | nothing | stumbles the player into the hard-landing lockout, on contact — see below |

Every field not named in that table is ignored by that effect. There is no
`BLOCK_WALKING`, `BLOCK_FALLING`, `BLOCK_LANDING`, `BLOCK_FALL_UNCONTROLLED`
or `BLOCK_CROUCH`, and there never will be: each of those either strands the
state machine or hangs the body in mid-air with nothing to run. Crouch in
particular is a slide's only exit under a low ceiling. The way to stop a
player crouching is geometry, not a status.

### `STAGGER` fires on contact, and then leaves you alone for a moment

Barbed wire cuts you when you touch it. `STAGGER` stumbles the player the tick
it lands, **including in mid-air** — so a volume tall enough to cover a fence
charges the vault at the moment it is taken, not on the far side. The lockout
starts there too, which is why the time spent unable to move on the ground is
noticeably shorter than `lockout_time`: most of it was spent falling.

**It is a knock-down, not a wall.** The cut takes the upward half of the arc
and most of the speed — `landing.stagger_keep_ratio` of the horizontal is what
survives — so the body carries on forward and down instead of stopping dead
above the fence. Wire is there to punish forgetting to tuck, not to make an
obstacle impassable.

`seconds` is therefore an ordinary duration here, and a short one is fine: the
status is spent the instant it fires, so anything above a tick or two only
matters if the player is immune when it arrives.

**Staying in the wire keeps hurting, but cannot trap you.** When a landing
lockout releases it arms `pawn.stagger_immunity_time` — a window in which a
new `STAGGER` is eaten rather than queued. Without it a volume renewing its
stagger would re-fire on the tick the lockout ended, and since the lockout
refuses movement input there would be no tick in which to walk out. The window
has to outlast the time it takes to cross the wire, not the time it takes to
react; a metre or two of wire needs well under a second.

The immunity is armed by *any* landing lockout, not only one a stagger caused
— a body that has just picked itself up off the floor is exactly as unable to
absorb another stumble.

**A wire the player can stand in needs a `refresh_interval`.** Without one the
volume charges on entry and never again, so a run of wire along a wall can be
walked end to end having paid once. Give it a short interval — `0.25` — and the
cadence looks after itself: the stagger fires, the lockout refuses input for
`landing.lockout_time`, the immunity window opens for
`pawn.stagger_immunity_time`, and the next renewal past that bites again. The
window is the only tick the player can move in, so it is also the only chance
they get to step off.

DO NOT write that cadence as an interval of its own. Three seconds between hits
is `lockout_time + stagger_immunity_time`, and a third number would have to be
kept in step with both by hand.

**That cadence is for standing still, not for coming back.** Walking into the
volume charges immediately, even inside the escape window — otherwise the
window is also a window in which the player can hop off the wire and back on
unharmed, and a run of wire becomes a platform to bounce along. The volume is
the only thing that can tell entering from renewing (nothing tracks
membership), so it says which, and the body decides what that means. Escaping
is untouched: leaving is not entering, and only a player who chooses to step
back on pays again.

**`BLOCK_CROUCH` forbids the choice, not the posture.** A body that cannot
stand up is not using a technique, so a headroom-forced crouch goes through
regardless — otherwise a slide under a low ceiling would have no exit, and
because slide steering is deliberately slow it could not be driven out either.
Blocking the crouch stops the player *ducking into* a crawl space; it does not
strand them in one.

### Attaching a modification to a region rather than to a moment

Nothing tracks who is inside a volume — there is no exit handler and no
membership list. A region-wide modification is a short-lived status the
volume keeps renewing:

- Set `refresh_interval` to how often it re-applies, e.g. `0.05`.
- Set each row's `seconds` to **at least twice** that, e.g. `0.15`.

The status is then continuously renewed while the player is inside and lapses
on its own shortly after they leave.

**Both numbers want to be small, and the reason is the exit.** `seconds` is
not only the renewal margin — it is also how long the modification outlives
the player leaving the volume. What lapses is the last renewal, so the lag on
the way out is `seconds` minus however long ago the last one fired: somewhere
between `seconds - refresh_interval` and `seconds`. A 0.5 / 1.5 pairing is a
full second to a second and a half of still being slowed after the red floor
is behind you, and that is felt. 0.05 / 0.15 costs twenty polls a second per
volume and brings it down to about a tenth of a second.

Do not give `seconds` the same value as `refresh_interval`: both clocks then
start from the same number and subtract the same delta, so the status expires
on the very tick it is renewed and survives only because the volume is ordered
ahead of the player. That is zero margin — anything that lets the two drift
puts the expiry a frame ahead of the renewal, and one frame is enough for a
buffered jump to fire inside a no-jump region. Twice the interval leaves a
whole interval of slack.

Leave `refresh_interval` at `0` for a one-shot: a status with a fixed
`seconds` that starts counting the moment the player crosses the boundary and
runs out wherever they happen to be.

### Running barbed wire along a path

`BarbedWire` (`scripts/level/barbed_wire.gd`) is a `Path3D` that winds a coil
of concertina wire about its own curve. **The curve is the AXIS, not the
strand**: drag it along the top of a wall and the coil wraps it.

1. **Add Node → `BarbedWire`**, and drag its curve where the wire should run.
2. Set `coils_per_metre` for how tight the concertina reads, `coil_radius` for
   how far the loops stand off the path, and `wire_radius` for the strand's own
   thickness. `barbs_per_metre`, `barb_length` and `barb_seed` place the barbs.
3. That is all it does.

**It produces geometry and nothing else** — no hazard, no collision. That is
deliberate, and it is why the three can be combined freely:

- To make the wire *hurt*, put a `ModifierVolume` beside it carrying `STAGGER`.
  The stagger knocks the player into the landing lockout, which also takes
  their hands off any ledge they were holding.
- To make a wall *unclimbable*, give its top a collider the ledge probe will
  not accept. `Probes.ledge_query()` refuses any surface whose `normal.y` is
  below `PawnConfig.walkable_floor_z` (0.71), so a ridge along the top works if
  it is **taller than half its width** — that is `atan(h / halfwidth) > 44.8°`.
  This is how the original does it, and it costs nothing at runtime: there is
  no rule to evaluate, because there is no ledge to find.

Wire that is merely decorative wants neither of those, and gets neither.

`samples_per_coil` is the biggest lever on the triangle count, but do not
trade the coil's shape against it: it is what makes a loop round rather than
hexagonal, and the triangles it costs are not worth having. A single character
model here carries about forty thousand; 140 m of coil down both walls of the
test corridor measured 6.81 ms a frame against 7.23 ms with the wire deleted,
which is noise. The configuration warning is set where a run stops being wire
and starts being a mistake, not where a GPU starts to care.

### `layer_priority`

Which layer this volume speaks on, when two volumes claim the same status at
once. Higher wins; equal layers keep whichever arrived first and push one
warning naming both. **Leave it at 0 unless volumes actually overlap** — it
exists for the case where a small exception box sits inside a large regional
one, and the small one has to win.

It is deliberately not called `priority`: `Area3D` already exports one, and
that one governs which overlapping area's gravity and damping overrides win.
Raising a status layer must not silently reorder physics.

### `max_trigger_count`

How many **entries** this volume acts on; `0` is unlimited. Refreshes never
count — a polling volume renews many times per visit, and charging those
would spend the whole budget on the first tick. `1` is "only on the first
lap"; `0` is "every lap".

The count is about one life: dying resets it, so a level that cripples the
player at its start cripples them again after a death there.

An accepted trade comes with that: a respawn inside a volume re-applies its
statuses without charging the count (a respawn is not a player-initiated
entry, and the reset zeroed the count moments earlier anyway). So a life that
*begins* inside a `max_trigger_count = 1` volume ends the respawn with the
count still at zero, and walking out and back in during that life can act
once more.

### What the configuration warnings mean

The node reports these in the scene tree, before the level is ever run. Every
one of them is silent at run time — the volume simply never fires, or fires
with a payload nothing reads.

- **No CollisionShape3D with a shape** — the volume can never be entered.
- **Neither apply nor remove is set** — it does nothing.
- **An empty row in `apply`** — a `StatusSpec` slot left null.
- **SPEED_CAP with amount ≤ 0** — pins the player in place, which reads as
  the level having hung.
- **BLOCK_INTEREST_LINE with no subject** — blocks nothing; the effect
  addresses a line by its `tag`.
- **refresh_interval is set but a status lasts forever** — renewing is how a
  status is meant to expire on the way out, and `INF` is what stops it ever
  doing so, so it survives leaving the volume.
- **A status no longer than the refresh interval** — it expires on the very
  tick it is renewed, with no margin at all. See above.
- **refresh_interval shorter than one physics tick** — the one entry here that
  is not a broken volume. It refreshes every tick, which is already as often
  as anything can, so a value like `0.008` behaves exactly like one whole
  tick and the number typed means nothing.

## ⚠️ Do not put comments in a `.tscn`

Godot's editor rewrites any scene it saves, and it does not preserve `;`
comments. `me_shaft.tscn` was authored with about seventy lines of them
explaining where every dimension came from; one capture run later the file had
gone from 234 lines to 163 and every one of them was gone, along with any
property the editor judged equal to its default.

So a scene file holds geometry, and **the reasoning behind the geometry lives
here**. The same round-trip is what assigns `uid://` values, which is why a
hand-authored scene should omit them and let the editor fill them in — see
`.claude/skills/authoring-godot-scene-files`.

## The Mirror's Edge shaft whitebox

`scenes/debug_levels/me_shaft.tscn`, a CSG reconstruction of the original's
chapter-1 shaft climb — ✅ the owner: "几乎融入了所有的基础技巧，需要利用多次
Grab反身跳来逐渐到达最高点".

### Why the ducts are 2.0 m apart

This is the whole design, and it is derived from `GrabConfig`, not chosen by
eye. A ledge can only be grabbed while it sits between `min_wall_height`
(1.8 m) and `ledge_max_height` (2.8 m) **above the feet** — higher than a
standing body, which is what makes a grab a grab rather than a step.

| Spacing | What the player does |
| --- | --- |
| 1.0 m | plain jump every time (peak is 1.24 m); the grab never fires |
| **2.0 m** | every ledge lands inside the window: grab → mantle → stand → turn → jump |

### Why the shaft is 3.2 m across

The ducts stand 1.0 m proud of each wall, leaving a 1.2 m gap. A hang jump
leaves at `jump_speed` 6.3 m/s with only `jump_speed_up` 1.6 m/s of lift, so it
travels about **1.26 m** before it is back to the height it started at. A wider
shaft cannot be crossed from a hang at all.

⚠️ That 1.26 m is the FLAT case. `GrabMove._launch_direction()` uses the
camera's full 3D forward, so looking up trades reach for height — 45° gives
1.14 m of rise but only 4.45 m/s across, and straight up gives 1.95 m of rise
and almost no travel. ✅ The owner: "Grab时回头往斜上方看，可以跳的比较高，但
肯定没平视时远".

### Why the vent is 1.0 m tall

A standing body is 1.8 m and cannot enter; a coil or a crouch is 0.9 m and can.
Its lip sits 1.0 m above the last duct, inside the 1.24 m jump peak but not by
much — ✅ the owner on the original's own version: "时机很难把握，而且很难对准".

### Structure

One `CSGCombiner3D` with `use_collision`, so the boolean result IS the
collision — `factory_hall.tscn` needs three nodes per box to keep a mesh and a
shape in step. ⚠️ **Child order is the boolean**: `Outer` fills, `Cavity`
hollows, the ducts add back, the vent cuts through last. Moving a duct above
`Cavity` deletes it instead of adding it.

Runner-vision red is a SEPARATE combiner with no collision, so a hint can never
be stood on.

### Lighting, and two ways to get it wrong

The first version rendered **completely black**, the fix rendered
**completely white**, and both were caught with `tools/capture.gd` rather than
by reading the file. Brightness is not something to reason about.

* A `DirectionalLight3D` cannot light a sealed box. A closed room needs
  fixtures inside it — four `OmniLight3D` down the shaft, which is what the
  original has.
* `ambient_light_source = COLOR` is **not enough on its own**.
  `ambient_light_sky_contribution` defaults to 1.0 ("take all ambient from the
  sky"), so the colour is never consulted. Set it to 0.
* SDFGI resolves real occlusion, so it contributes nothing inside a sealed box
  and was the original blackness. Off here: 112 fps against 30, in a room of a
  dozen boxes.
* With light finally arriving, white walls clip instantly. ACES tonemapping
  plus backing every value off (ambient 1.1 → 0.35, lamps 2.4 → 1.1, albedo
  0.90 → 0.82) is what made the geometry readable.

📌 The dimensions have **no test pinning them**. They are exactly the kind of
number `docs/feel-backlog.md` 57 says not to assert on: tuned by eye, wrong at
a glance.
