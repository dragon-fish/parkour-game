---
name: reading-ue3-surface-data
description: Use when an extracted Mirror's Edge surface looks wrong — a colour on the wrong face, a texture stretched or cropped, a wall, ceiling or duct drawn flat grey, a facade that is white here and orange in the original, geometry that reads as flat where the original has relief — or before trusting any claim about what a material does.
---

# Reading the original's surface data

## Overview

Five separate faults here all looked like "the material is wrong", and every
one of them was a field in the package that the extractor read and threw away,
or never read. Before theorising about the baker, check that the surface is
being told which material, which coordinates and which way is out.

## An element's MaterialIndex is not its position

`FStaticMeshElement` carries its own `MaterialIndex`, and **that** is what a
placement's `StaticMeshComponent.Materials` array indexes. It is not the
element's ordinal. They differ:

```
S_RooftopStructure_06
  element 0  MaterialIndex=0   2501 tris   the structure
  element 1  MaterialIndex=3     72 tris
  element 2  MaterialIndex=1     17 tris   the roof deck
  element 3  MaterialIndex=2    112 tris   the side band
```

Indexed by ordinal, the blue meant for the side band landed on the roof deck
and the deck's grey on the band — a clean swap, and one that looks like a
plausible art choice from inside the game. `slot` on every extracted surface
is this field; `surface_slots` on the built mesh maps a built surface to it.

A skeletal mesh's section already names its material by index, so that index
is the slot.

## The UV set belongs to whatever DRAWS the surface

A mesh in the library carries **one** coordinate set per surface, chosen when
it is built. Choose it from the element's own material and an overridden slot
gets the wrong one: the billboards' ad elements carry `M_TestAd_01`, a 4x4
placeholder on set 0, and every ad painted over it wants set 1. Built on the
placeholder's set, an ad samples the lightmap atlas patch and shows one
stretched corner of itself.

`extract._override_uv_sets` resolves this per chapter. Two limits it cannot
lift, both reported rather than hidden:

- Within a chapter, a slot two placements override with materials wanting
  different sets keeps the element's own. About 44 surfaces game-wide.
- **Across chapters the library is shared and the last build wins.** About 30
  surfaces. This is the one order-dependence in the pipeline.

Do not assume set 0 is the texture set. On these meshes set 0 is the packed
lightmap atlas — every element inside 0..1, each in its own patch — and set 1
is the tiling one, running well outside 0..1. Measure the spans; do not guess
from the index.

## BSP surfaces carry a material and their own projection

`FBspNode.iSurf` (+20) names an `FBspSurf` (56 bytes) whose first field is the
material, with `pBase`, `vTextureU` and `vTextureV` following. Skipped, every
interior wall, ceiling and air duct in the game drew one flat palette grey —
sp01b alone has 4542 such faces across 71 materials.

UV is the original's own planar projection: `(point - base)` projected on each
texture vector, over 128 units per tile.

`RemoveSurfaceMaterial` is the mark for a surface compiled but never drawn. It
still blocks, so it belongs in the collision and not the mesh.
`DefaultMaterial` is the engine's checkerboard, and the original shows it too.

## A facade's colour can live only in the baked lighting

`MI_C_04_Facade_Color_Yellow` overrides **no** parameter of its parent. Nor
does `MI_C_06_03_Orange`, or most of the `_Color` and `_Storefront_` family.
They differ from their parent in one thing: `BakerColor`, which Beast used
when it baked the lightmap. Our bake of the instance is therefore identical to
the parent's, and correct for the original's runtime albedo — the colour the
player sees was never in the diffuse.

With no lightmaps the only record of it is `BakerColor`, carried as
`baker_tint` and applied behind `baker_tint_strength`. Two constraints:

- Only where the bake takes no colour of its own. A material that already
  tints itself would be tinted twice.
- **Carry the colour, not its level.** `BakerColor` is an albedo and the bake
  already says how bright the surface is; multiplied by a stored (0.5, 0.5,
  0.5) a plain wall came out half as bright for no reason.

### BakerColor is also an independent witness

It is what the level's own bake was told the surface looks like, so it audits
the expression evaluation from outside: where the bake and `BakerColor` agree,
the graph was followed; where the bake is grey and `BakerColor` is not, the
bake lost something. That comparison found this whole class. Compare
directions, not brightness, and treat 15-20 degrees as noise — a tinted
texture's mean includes its white.

## The Normal input was never evaluated

The baker read `DiffuseColor`, `EmissiveColor` and opacity and nothing else,
so every surface in the game was flat. The root's `Normal` input evaluates
like any other, and a sample arrives in the 0..1 the texture stores.

- **Flip green.** The original's maps are DirectX-handed (+Y down), Godot
  samples OpenGL-handed (+Y up).
- A `Normal` that evaluates to a constant is a material with no map.
- An unsupported node contributes a flat 0.5, which read as a normal tilts
  every pixel sideways. A real tangent-space map has a blue mean near 1;
  below 0.6 the evaluation did not produce one.

## A material's name is not evidence

Twice here a conclusion was built on a name — `MI_RooftopStructure_01_Blue`
"is" the blue roof, `MI_C_06_03_Orange` "is" an orange the bake lost — and
twice the data said otherwise. The first was landing on the wrong element; the
second was faithful to the runtime and missing a lightmap.

Triangle count is not evidence of size either: the roof deck in question is
17 triangles and 103 square metres, while the 2501-triangle element beside it
is pipes and railings. Measure area and normals.

What settles these: the field itself, the geometry's own numbers, and the
owner looking at the original at named coordinates. HUD (X, Y, Z) is our
(X, Z, Y), so a placement's position converts straight into somewhere to
stand.
