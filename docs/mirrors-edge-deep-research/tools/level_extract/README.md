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

**Normals.** The packed normal is at byte 4 of each vertex (TangentZ). A few
meshes were cooked with none, `(128, 128, 128)`; those are shaded flat and
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

**Only inline mips, up to `texture_max_px`.** Small mips are stored in the
cooked package, some LZO-chunked (tag `0x9E2A83C1`); the full-size mip lives in
the texture's source package and is deliberately not read.

**UV set and tiling come from the TextureCoordinate node** feeding the sample,
sometimes through a static switch; facade materials sample set 1. When a graph
samples several coordinates, the first sample with an explicit coordinate
decides: an unconnected sample is usually a tiling-1 variation mask, and taking
its tiling turned the chain-link fence into one knot per panel.
