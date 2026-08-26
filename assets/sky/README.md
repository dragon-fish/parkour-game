# Sky

`day_sky.tres` is the **one** sky every level uses. `templates/base_level.tscn`,
`scenes/debug_levels/animation_lab.tscn` and `tools/arena_builder.gd` (which
generates `scenes/main.tscn`) all reference this file rather than each building
a `ProceduralSkyMaterial` of their own — which is what they used to do, in four
places that could drift apart.

## Swapping the sky

Open `day_sky.tres`, change the **`panorama`** field of its
`PanoramaSkyMaterial` to another `.hdr` in this folder. That is the whole
operation: one file, one field, and every level follows.

Three are checked in, all 2K Radiance `.hdr`:

| File | Look |
| --- | --- |
| `kloofendal_48d_partly_cloudy_puresky_2k.hdr` | Partly cloudy daylight. The current one, and the most generic of the three. |
| `kloofendal_43d_clear_puresky_2k.hdr` | Cloudless. The high-key Mirror's Edge-leaning option. |
| `kloppenheim_06_puresky_2k.hdr` | Bright daylight with cloud, higher contrast — harder sun, so shadows and light shafts read stronger. |

## A level that wants its OWN sky

Assign a **different `Sky` resource** to that level's `Environment` — copy
`day_sky.tres` to a new file, point its panorama somewhere else, and select it
in the inspector. Do NOT right-click > Make Unique on `day_sky.tres` inside one
level: that embeds a private copy in that scene, and the level then quietly
stops following any future change to the shared one.

This is the opposite of how `FogConfig` works, and the difference is
deliberate. Fog is per level by default (each level's copy is
`resource_local_to_scene`, so tuning one never moves another). The sky is
shared by default, because "every level in this game looks like the same
afternoon" is the thing you usually want, and one radiance bake is cheaper
than one per level.

## Licence

All three HDRIs are from [Poly Haven](https://polyhaven.com/hdris) and are
**CC0** — public domain, commercial use fine, no attribution required. That is
why they live in this repository rather than in the `.private` submodule the
licence-bound assets use.

## Why 2K

A sky is background and reflection, never inspected up close. 2K `.hdr` is
4–5 MB each; the 4K versions are ~18 MB for a difference nothing in this game
is close enough to see. `Sky.radiance_size` (left at Godot's default 256) is
what actually governs reflection quality, and it is independent of the source
resolution.
