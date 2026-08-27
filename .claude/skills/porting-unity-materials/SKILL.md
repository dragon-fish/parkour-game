---
name: porting-unity-materials
description: Use when bringing an asset authored for Unity into Godot — a VRChat avatar, a `.unitypackage`, a lilToon/Poiyomi material, an FBX whose textures look washed out, flat, over-bright or tinted wrong after import — or when deciding whether a Godot colour uniform needs `source_color`.
---

# Porting a Unity-authored material into Godot

## Overview

The mesh imports. The material does not. An avatar built for Unity carries
its look in a `.mat` file holding several hundred parameters, and a
hand-rebuilt approximation of it will be wrong in ways that read as "the
textures are bad": washed out, low contrast, dyed by the level, flat.

The textures are almost never bad. **The composite is.** Recover it from the
file, not from memory.

## Read the .mat, never your memory

A `.unitypackage` is a gzipped tar. Each asset is one directory named by its
GUID, holding `asset` (the real bytes), `asset.meta` (import settings) and
`pathname` (where it lived). Build the GUID→path map from every `pathname`,
then pull the `.mat` files — they are plain YAML.

That file answers questions guessing cannot:

- **The blend maths.** lilToon multiplies each matcap layer by the albedo
  underneath when `_MatCapMainStrength` is 1, then weights it by
  `_MatCapBlend * matcapColour.a * mask.rgb`. Skipping the multiply turned an
  Add/Screen matcap into a bleach pass here: every dark texel climbed toward
  white and a white costume with black panels lost its whole design. Skipping
  the colour's *alpha* doubled a layer that ships at 0.463.
- **Which slot holds which texture.** Two materials had their first and
  second matcap swapped, and one had a main texture the original never gave
  it — printing an unrelated UV layout onto the mesh.
- **The `.meta` files too.** `sRGBTexture: 1` on *every* texture, masks
  included, means the original samples a mask through the same gamma decode
  as a colour. Sampling it raw reads roughly double the weight at mid grey.

## The shader variant decides, not the field that looks like it

`_UseOutline: 0` sat in all five materials of an avatar that visibly had
outlines. That field is inspector bookkeeping. What decides is the shader
GUID in `m_Shader`: matching it against the shader package's own `.meta`
files identified `lts_o.shader` — lilToon's **outline** variant. The same
check separates opaque from cutout from transparent.

Fetch candidate `.meta` files from the shader's upstream repository and
compare GUIDs. Unity GUIDs are stable across versions, so this works even
when the package itself is not in the archive.

## Three colour-space rules in one asset

| Value | Space | Godot |
|---|---|---|
| `Color` in a `.mat` | already linear, sometimes above 1.0 | uniform with **no** `source_color` |
| Texture with `sRGBTexture: 1` | sRGB, masks included | sampler **with** `source_color` |
| A shader uniform's **default** | not gamma-decoded | see below |

That third row is a Godot trap, not a Unity one: **a `vec3` default written
in the shader is used as-is, while the same three numbers set on the material
are decoded.** With `source_color` on the uniform the two disagree. Dropping
the hint and keeping every colour linear makes them agree, and matches how
the `.mat` stored them anyway.

## What Godot 4 will not give you

- **No writable `AMBIENT_LIGHT`**, in `fragment()` or `light()`. Godot 3 had
  it. A toon shader that clamps *total* incoming light (lilToon's
  `_LightMinLimit`/`_LightMaxLimit`) therefore cannot clamp the environment's
  ambient after the fact. Switch it off for the material
  (`ambient_light_disabled`), carry the floor in `EMISSION`, and let `light()`
  add only the headroom under the ceiling.
- **No light vector in `fragment()`.** Any term shaped by NdotL either moves
  into `light()` or gets dropped — say which, in a comment.

## Prove it by rendering one layer at a time

Reasoning about a composite is how the wrong layer gets blamed. Force one
layer off and render: with every matcap forced to 0, the black panels, gold
trim, teal wingtips and red irises all came back at once — which located the
fault in the matcap composite in a single frame, before a line was changed.

Read `.claude/skills/verifying-visuals-headlessly/SKILL.md` before trusting
any of these probes. Two of them lied here: one overwrote the shader defaults
it was supposed to be measuring, so three "default" runs rendered the same
image; and MSAA never reaches the `--script` capture path at all, in either
backend, so antialiasing cannot be judged from it.

## Common mistakes

- **Tuning a number by eye to fix a structural error.** The washed-out look
  was a missing multiply, not a value that needed lowering.
- **Copying only the textures the material names in its main slots.** Outline
  width masks, emission masks and second matcaps live in slots easy to skim
  past, and their absence looks like a colour problem.
- **Adding `source_color` because the uniform holds a colour.** Ask where the
  number came from first.
