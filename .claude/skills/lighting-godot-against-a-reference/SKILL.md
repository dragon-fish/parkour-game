---
name: lighting-godot-against-a-reference
description: Use when matching a Godot scene's lighting, sky or exposure to reference screenshots, or when a sky, ambient or shadow setting seems to do nothing or leaks light where it should not.
---

# Lighting a Godot scene against a reference

## Overview

Matching screenshots is measurement work: crop the same region of the
reference and the render, compare numbers, change one thing. The traps
below each cost part of a session on the Mirror's Edge levels; every one
looked like a tuning problem and was not.

## Measure, do not eyeball

Render from the reference's camera spot, then compare mean colour of named
regions (a Pillow script over both PNGs). A region that reads as "a bit
dark" is often 3x too dark. Framing differences (FOV, pitch clamp) make some
regions incomparable; pick regions that are the same surface in both.

## Traps

**`source_color` gamma-decodes a colour you meant as linear.** A shader
uniform declared `: source_color` and set from GDScript is treated as sRGB
and converted to linear. Passing a value that is already linear darkens it
by a power of 2.2: a sky specified at 0.4 rendered at 0.13, and three rounds
of "why is the sky so dark" followed. Declare colour uniforms without the
hint when the code computes linear values, and pass them as `Vector3`.

**The visible sky and the lighting sky are one thing.** `Environment.sky`
is what the camera sees, what `AMBIENT_SOURCE_SKY` integrates, and what
SDFGI reads (`sdfgi_read_sky_light`), and SDFGI ignores
`ambient_light_energy` and `ambient_light_source` when the background is a
sky. A dome bright enough to look right lights every shadow to daylight. To
decouple, draw the visible dome on an inverted sphere mesh round the camera
(`unshaded`, `fog_disabled`, following the camera each frame) and keep the
Environment's sky as the dim lighting sky. See `tools/me_level/me_dome.gdshader`.

**Soft directional shadows leak through far roofs.** With
`light_angular_distance` above 0 the PCSS penumbra estimate for a blocker
80 m away let the sun light an underground hall in full. It also dithers
every penumbra into speckle without TAA. Keep it at 0 and raise
`rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality`
instead.

**SDFGI may bounce none of your lamps.** Measured on the extracted levels: a
test OmniLight lit a corridor identically with SDFGI on and off, on Vulkan
and on D3D12, whatever the cell size, occlusion, shadow or bake mode. SDFGI
still occludes the sky ambient indoors (turning it off makes interiors
brighter, not darker). Do not tune `sdfgi_energy` expecting interiors to
fill; scale the lamps.

**A manifest's copy of the config is the config at extraction time.** A
builder that reads dials out of `manifest["config"]` builds yesterday's
dials with no error. Read tunables from the config file the build was asked
for.

## Verifying

Bisect with variants, one setting per render, and keep the numbers in the
same table as the reference. A setting whose every value renders the same
image is either not applied or overridden downstream (Arena rewrites the fog
from `FogConfig` every frame; the env node in a rebuilt geometry scene keeps
only the values the builder set). Say what was measured and where it still
differs.
