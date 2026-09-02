---
name: verifying-visuals-headlessly
description: Use when a change affects what is on screen — materials, animation, layout, camera framing — and you must confirm it without taking over the user's desktop, or when a measurement script reports something that contradicts what the user sees.
---

# Verifying visuals without stealing the desktop

## Overview

An agent cannot claim a visual change works because the code looks right.
It also must not launch a windowed game on a machine somebody is using: on
this project the level grabs the mouse pointer on `_ready()`, so any
windowed run yanks the cursor away from the person at the keyboard.

Two tools cover almost everything: a **capture script** that renders a scene
to a PNG you then read, and a **probe script** that drives the real objects
and prints numbers.

## Quick reference

| Question | Tool |
|---|---|
| Does it look right? | Capture a PNG, then read the image |
| Does the value change over time? | Probe: drive it and print a trace |
| Does the structure exist at all? | Test in the suite (survives, runs in CI) |
| Does it feel right? | The user. Not you |

```bash
# Rendering needs a real context: NO --headless, small window, hard backstop.
Godot --path . --resolution 960x540 --quit-after 300 \
  --script res://tools/capture.gd -- res://scenes/ui/main_menu.tscn out.png 90
```

Headless is right for logic and structure, and wrong for anything that has
to be drawn — the renderer is a dummy, so spring simulation, draw order and
materials all report as if fine.

## The capture path cannot see everything

Antialiasing is the known blind spot. MSAA never reaches a `--script`
capture — not at runtime, not from `project.godot`, and not on either the
D3D12 or the Vulkan backend. Four settings produced one identical edge
histogram. Judge it in the running game, or say it was not judged.

The general rule: **when every value of a setting renders the same image,
suspect the harness before concluding the setting does nothing.** A real
difference of zero and a path that never applies the setting look alike from
here, and only one of them is a finding.

## Headless does not merely fail to DRAW — it fails to REMEMBER

Some render state is written straight through to the server, and a headless
run's server is a dummy that keeps nothing. Reading it back returns the type's
zero value, silently, with no error anywhere.

Measured here on `MultiMesh`: set one instance's transform to `(7, 8, 9)`, read
it back with `get_instance_transform()` under `--headless`, get `(0, 0, 0)`.

That makes **any headless test asserting placement by reading a transform back
vacuous**, and it fails in the most expensive direction — every instance reads
as identity, so a test that says "these are all inside the box" passes no
matter where the code actually put them. One such test in this repo stayed
green after the centring term it existed to protect was deleted outright.

**Keep the value on the CPU side and assert that.** If gameplay code needs to
know where a cube is, it needs a real answer anyway, so a named field on your
own data is not test scaffolding — it is the fix. Push to the server for
drawing; never read back from it to find out what you asked for.

Suspect the same shape anywhere else state is written into a server object
rather than kept in the node: instance custom data, per-instance colours,
immediate-mesh contents.

## Your probe lies too

A probe is code you wrote in one minute to judge code you wrote in ten. It
has bugs, and its bugs read as *findings*. In one session here, probes
"proved" a character's spring chains did not exist and that a chain never
deviated from rest — both false, while the user was looking at the correct
behaviour on screen and telling me so.

Both had the same shape: **the probe measured before the thing existed, or
measured against the wrong baseline.**

Before believing a probe that contradicts the user:

1. **Print the inputs, not just the verdict.** Chain count, clip name, bone
   index, node path. A zero in the inputs is a probe bug, not a finding.
2. **Await the frames the engine needs.** Deferred builds, animation poses
   (~5-6 frames before bones move), physics ticks. Reading on frame 0 gets
   you rest pose and empty arrays.
3. **Measure a known-good baseline in the same run.** If the reference model
   also reads zero, the probe is broken.
4. **The user's eyes outrank your script.** When they say "it moves and your
   number says it doesn't", the number is wrong until proven otherwise.

## Report what the run showed

Say what was verified and how — "captured at 960×540, the panel is centred"
— and say plainly when something was not tried in a real session. "Not play-
tested" is a complete and acceptable sentence; a claim of feel is not.

## Common mistakes

- **Launching the windowed game to "just check".** It steals the pointer.
  Interactive verification belongs to the user, always.
- **Reading a PNG's filename instead of the PNG.** Open the image.
- **Reporting a probe result as fact without the inputs.** Half the numbers
  in a broken probe look plausible.
- **Using wall-clock time to judge engine timing.** Frame pacing and wall
  clock diverge; print the engine's own clock or count frames.
