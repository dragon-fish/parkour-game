# Mirror's Edge level extractor

Turns a section of an original Mirror's Edge (2008) level, read from a local
install, into a playable level of this project: render meshes, collision,
lights, and gameplay volumes. Design: `docs/superpowers/specs/2026-09-17-me-level-extractor-design.md`.

**Nothing produced here may enter this public repository.** Configs and
outputs live in the `.private` submodule; the extractor and the Godot builders
contain no original data.

## Use

```powershell
# 1. Extract (Python via uv; writes _local/me-reference/level-extract/<id>/)
uv run --no-project --python 3.12 --with lzallright --with numpy `
    docs/mirrors-edge-deep-research/tools/level_extract/extract.py `
    .private/scenes/local_debug_levels/mirrors_edge/levels/sp02_stdp.json

# 2. Build the mesh library, geometry scene, and (first time only) the shell
.engine/Godot_v4.7.1-stable_win64_console.exe --headless --path . `
    --script res://tools/me_level/build_level.gd -- `
    res://scenes/local_debug_levels/mirrors_edge/levels/sp02_stdp.json

# 3. Structural checks
.engine/Godot_v4.7.1-stable_win64_console.exe --headless --path . `
    --script res://tools/me_level/verify_level.gd -- `
    res://scenes/local_debug_levels/mirrors_edge/levels/sp02_stdp.json
```

`--rebuild-interactions` on step 2 **replaces the shell and every edit in it**.
Without it an existing shell is never touched. `verify_level.gd` compares the
shell against the manifest, so it only holds for a shell nobody has edited;
the tutorial has its own `levels/verify_sp00_tutorial.gd`.

Config keys are documented at the top of `packages.py`. Chapter names and the
original checkpoint descriptions are in the install's
`TdGame/Localization/CHS/TdGame.chs` (UTF-16): look there, not in memory.

The SP01 resource directory contains **two** story maps: SP01a (Prologue,
`Edge_p.me1`) and SP01b (chapter 1, `Escape_p.me1`). Their private configs
are `sp01a_edge.json` and `sp01b_escape.json`; both retain `chapter: SP01`
and select the map with `persistent`. SP02 is chapter 2, not chapter 1.

Both SP01 configs enable `split_sections`. The builder writes a chapter
shell, one editable shell and geometry per section, and shared chapter
geometry. Open an individual section to edit its blockout, or set the
chapter's `Sections.editor_preview` to a section name. At runtime every
section is instantiated; this improves generation/editor handling, not
runtime streaming. `verify_level.gd` checks all sections together, including
interaction counts, mover targets and floors under checkpoints.

Asset-free ladder regression checks:
`uv run --no-project --python 3.12 docs/mirrors-edge-deep-research/tools/level_extract/test_annotations.py`.

## Traps, each of which silently lost part of a level

**Coordinates.** UE3 is left-handed. The axis map `(x, z, y) / 100` has
determinant -1; a map with +1 produces a perfectly measured mirror image.
Triangle winding flips with it (`static_mesh.py`).

**Property offsets are not fixed.** Archetypes start their tagged properties
at +4, placed actors at +32. `MapReader.props()` tries every candidate offset.

**Cooked objects are deltas against their archetype.** A placed
StaticMeshComponent often carries only a lightmap; the mesh is on the
archetype. Prefab instances (`PF_*_Arc*`) keep it on an archetype in a
different package, and the chain can end in `Engine.u` class defaults.
`packages.resolved_props()` follows the whole chain across packages, and an
object reference read from another package is carried as `('ext', reader,
index)` because an index only means something in the package that wrote it.

**Meshes are imports.** `Tutorial_p` exports zero StaticMesh objects; its
placements import from shared `.upk` packages, which ship uncompressed.

**Prefab templates are not placements.** Only actors whose outer is a `Level`
are placed. The tutorial's old manifest carried a whole building at the origin
(`S_C_02_02_F`, `S_C_02_02_R`) that exists in no level.

**No convex hull does not mean no collision.** Collision class per placement:
`CollideActors`/`BlockActors` false on actor or component means none; a mesh
with simple shapes and `UseSimpleBoxCollision` uses them; anything else collides
per triangle with the surfaces whose `EnableCollision` is set. Filling hull-less
meshes with bounding boxes turned light-shaft cards and hollow rings into walls.
That per-triangle is the fallback when a mesh has no simple collision is
`[ME:INFERRED]` from engine behaviour, not verified in the game.

**Materials decide what a surface is.** A light shaft is an `BLEND_Additive`,
`MLM_Unlit` material; drawn opaque it is a grey slab. The extractor follows
MaterialInstance parents to the root Material for `BlendMode` and
`LightingModel`; the mesh library maps additive, translucent, modulate and
unlit surfaces to distinct materials. Masked surfaces (gratings) are drawn
solid until textures exist.

**Two-sided means the material says so.** `TwoSided` is read from the root
Material; masked and translucent are not two-sided by themselves, and drawing
a storefront from both sides lit the inside of its building. A two-sided
surface is built as a second, reversed copy, never with `CULL_DISABLED`: a
placement with a mirroring transform (negative DrawScale) gets Godot's
`FRONT_FACING` inverted, so its outside renders black.

**Normals.** The packed normal is at byte 4 of each vertex (TangentZ). A few
meshes were cooked with none on some or all vertices, every byte 127 or 128
(a zero vector, rounded either way); those are shaded flat and
listed in the report. Any other non-unit normal is a parse error.

**Lights are baked with Beast.** With `bUseBakerColorAndBrightness`, the
brightness that mattered is the actor's `BakerBrightness`; the component's
`Brightness` is usually 0. There is no known conversion: `me_lights.gd`'s
`energy_scale` is a dial. `TdAreaLight` carries a PointLightComponent.

**BSP carries floors.** The compiled world BSP holds ground some starts stand
on. Brushes are not triangulated separately: that would fill CSG holes.

**Volume data is partly stale.** Barbed wire Start/End/SplineLocations can be
zero or NaN, so the wire follows its brush's long axis. Swing volumes are
vertical triggers: the bar is the horizontal pole or pipe mesh inside (the
Stormdrain swings on ceiling pipes). Ladder facing is the volume's WallNormal,
which points out of the wall.

Some ladders have identical cooked Start/End and spline points. As with
out-of-bounds cooked splines, the extractor reconstructs these from the
original `PawnLadderLocations`; the builder must not create a zero-length
interaction line. Swing bars can also be horizontally rotated catwalk supports.

**Section bounds.** Chapter checkpoints live in the persistent `*_p` package.
Only those inside the section's own packages are kept: slices reach deep into
neighbouring sections and `_Bac` is the skyline.

**Blocking volume flags.** `bExludeHandMoves` / `bExludeFootMoves` (sic) default
from `Engine.u`'s `Default__BlockingVolume`; the extractor refuses a volume whose
archetype is outside its package and does not set both.

**Textures are baked, not copied.** The original packs data into channels and
tints with parameters: the skyscrapers' `_D` texture is R and G detail plus a
B glass mask, averaged and multiplied by a `DiffuseColor` parameter, and drawn
as-is it is a yellow and blue stripe. `materials.py` evaluates the part of each
material's expression graph that reaches `DiffuseColor` and `Opacity`/`OpacityMask`
per pixel (texture samples with channel masks, arithmetic, lerp, parameters with
MaterialInstance overrides, static switches at their defaults). Cube maps,
pixel depth and fresnel become 0.5. An `ExpressionInput` is itself a tagged
struct: `Expression` plus `MaskR/G/B/A`.

**A map package's texture keeps only mips up to 64 px.** The rest are flagged
as stored elsewhere, and there is no `.tfc` in the install: the full texture is
in the shared `.upk` of the same name under `CookedPC` (`packages.texture_sources`,
indexed once). Mips are LZO-chunked (tag `0x9E2A83C1`); `texture_max_px` caps
the mip taken. Bakes are stored as PNG in `materials.json`.

**Surface behaviour is a PhysicalMaterial flag.** Soft landing
(`bEnableSoftLanding`) and the RumpSlide chute (`bEnableUncontrolledSlide`) are
booleans of the `TdPhysicalMaterialProperty` behind a `PhysicalMaterial` in
`TDPhysicalMaterials.upk`. The mesh's BodySetup names one; so does each surface
material's `PhysMaterial`, and the two disagree: Stormdrain's chute is one
surface of a mesh whose other surface is a wall. Surfaces carry
`uncontrolled_slide`, and the Godot library splits their collision into a
second shape the builder puts on its own body. A BlockingVolume's
BrushComponent can carry one too, as `PhysMaterialOverride`: Escape's
slanted-building chute is a volume with `PM_Glass_BulletproofSlide` lying a few
centimetres over a mesh with no slide flag, and the capsule stands on the
volume. Air walls carry the flags like surfaces do.

**A package in the chapter directory is not necessarily in the game.** Only
what the persistent level lists as `LevelStreaming*` ever loads. Escape ships
its two elevator slices twice, `_Slc` and `_Spt`, and streams only `_Spt`;
extracted together, a second car stood in the shaft. Section inference drops
unstreamed packages and lists them in the report as `unstreamed`.

**A name is not a mesh.** Subway_Bac holds two different `Vista_Mountains`
(`B_Vista.SP03` and `B_Vista.SP04`), Mall two `S_Policecar_01` from different
packages. The mesh library is keyed by name, so a clash would have one level
draw the other's mesh: both get their path as a suffix (`name@path`), and the
report lists them as `mesh_variants`. Imports are matched by path for the same
reason.

**An import's outer can be an export.** A package cooked into a map (a forced
export, class `Package`) holds imports of its own: Scraper's `M_FNMinimi`.
The export chain spells the rest of the path.

**A prefab's volume keeps its brush on the prefab.** Factory's server-rack
BlockingVolumes carry a delta BrushComponent; the hull and the move flags are
on the archetype in the prefab's package, read through the whole chain.

**Pain volumes are PhysicsVolumes.** `bPainCausing`, `DamagePerSec` and a
`DamageType` (the class default when unset, `None` when set to nothing) make
Escape's electric fences. One whose own Touch switches its collision off
(Factory's falling lift) hurts once per life.

**A section's swing bar can be another section's placement.** Section shells
search the whole chapter's placements for bars; a bar is any horizontal member
passing through the volume, and a member is the whole mesh only when it is
thin: Cranes hangs its bar on rods.

**The chapter's end is a touch, a long way up.** `SeqAct_TdLevelCompleted`
is reached from a touch through the outro (input off, a matinee, a delay, a
fade) and usually a remote event sent from another package. The extractor
walks up through all of it, only through a Gate's In (Edge's roof end opens
the gate; grabbing the helicopter goes through it), and records the touches
as `level_end`. The tutorial, the Mall and the Boat reach it no other way and have
none.

**A builder script is loaded without the autoloads.** A level script that
names one (`PauseUi`) fails to compile there and the shell saves the node
with no script at all; `verify_level.gd` checks that the Glass and LevelEnds
nodes have theirs. Grep a build log for `SCRIPT ERROR`, not only `ERROR`.

**Everything loads at once here; the original streamed.** A section's coarse
hull can stand where the neighbouring section's corridor is, because the
original never had both loaded (Escape's St1 building box over R1's corridor
to the elevator that streams St1 in). `collision_overrides` in the config
sets a mesh's collision class by hand for such cases, and for collision that
is faithful but unwanted (potted bushes that stop a climb).

**UV set and tiling come from the TextureCoordinate node** feeding the sample,
sometimes through a static switch; facade materials sample set 1. When a graph
samples several coordinates, the first sample with an explicit coordinate
decides: an unconnected sample is usually a tiling-1 variation mask, and taking
its tiling turned the chain-link fence into one knot per panel.
