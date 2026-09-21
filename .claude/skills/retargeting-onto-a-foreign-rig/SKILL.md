---
name: retargeting-onto-a-foreign-rig
description: Use when driving one skeleton's animation with another's — putting this project's character or the CC0 mannequin under the original's cutscenes — or when a retargeted body comes out with one leg, a chest turned sideways, wrung ankles or its head at hip height.
---

# Retargeting onto a rig that was never meant for it

## Overview

Godot retargets through `SkeletonProfileHumanoid`, which fixes what a rig
must mean: a body faces -Z, its left hand is toward +X, its rest is a T-pose.
Two rigs that each satisfy that profile can drive each other. A rig that does
not satisfy it produces a body that is wrong in a way no single measurement
taken inside either rig will show.

**The importer does this. Do not write it by hand.** A rest fixer was
attempted three ways here — normalise the rest, drive by world-space deltas,
splice a joint — and each produced a differently broken body. The whole
repair is two lines of `.import`.

## The working configuration

In the `.glb`'s `.import`, under `_subresources`:

```
"nodes": {
"PATH:<parent>/<Skeleton3D>": {
"retarget/bone_map": Resource("res://assets/animations/me_bone_map.tres"),
"retarget/rest_fixer/fix_silhouette/enable": true,
"retarget/rest_fixer/fix_silhouette/threshold": 0.0
}
}
```

The map is generated, not hand-written: `tools/build_me_bone_map.gd` for the
original's rigs, `tools/build_ual_bone_map.gd` for the animation pack's. A
`BoneMap` stores entries under generated property names against a profile
that has to exist first, so a script is cheaper than guessing the format.

`--headless --import` runs the importer with no window, so this belongs in a
build pipeline. Editing the map resource does NOT invalidate the import —
delete `.godot/imported/<file>-*` to force one.

At run time: `RetargetModifier3D` under the SOURCE skeleton, the driven
skeleton as its child, `profile` set, and **`enable` set to
`TRANSFORM_FLAG_ROTATION`**. The default passes position and scale as well,
which writes the source's coordinates onto the driven rig's bones.

## Three things that were wrong here, and what found each

### A world can be a quarter turn off and have no symptom

`common.to_godot` swaps Y and Z, which puts the original's forward on +X and
its right on +Z — a quarter turn from Godot's own convention. Geometry,
collision, spawn facings and movement all go through that one map, so the
world is self-consistent and the offset is invisible. **There is nothing to
be wrong against until something arrives with its own convention**, and the
humanoid profile is exactly that.

Left uncorrected, a rig's left-right axis lands on the profile's front-back
one. Both legs then receive the same rotation and the driven body comes out
with one leg, its chest ninety degrees round, its ankles wrung.

DO NOT correct this globally. Ten chapters rest on that map. `skeletal_glb.py`
turns the humanoid rigs alone (`UPRIGHT`, applied to node 0), selected by
bone names, and leaves pigeons and rats untouched.

### The rest fixer corrects orientations, not positions

So it straightened the arms into a T and left the legs where an A-pose had
them. The half it fixed is the half that reads as "looks fine", which is what
made the fault so hard to see: the upper body looked right and hid the cause.

A rig that rests in a game's idle stance — feet apart front to back, hands at
the sides, chest not square on — is not an A-pose or a T-pose and the fixer
only partly repairs it.

### Bone ORDER in a file does not give bone MEANING

The original's bones list as `... Spine, Spine1, ... SpineX, SpineXLeft,
LeftShoulder, ... Neck, Head ...`, which reads as a three-joint spine.
`SpineX` measures about as high as the head: it is a helper, not a vertebra.
Mapped to `UpperChest` as a third joint, the neck landed BELOW the upper
chest and the head ended up at hip height.

`Chest` means "what the neck and the shoulders hang off". Here that is
`SpineX`, and nothing maps to `UpperChest`. Measured cost of the joint left
unmapped: under 4 degrees. Measured cost of getting it wrong: a folded body.

## A measurement taken inside one rig cannot see this

Every check that stayed within a single skeleton passed while the body was
visibly broken:

| Check | Said | Why it could not see it |
|---|---|---|
| Per-bone orientation, relative to that rig's own hips | 0.0 deg | Blind to position; both rigs self-consistent |
| Bone lengths, rest vs pose | 0 stretched | Rotation cannot change them, and none was wrong |
| Bone names, hierarchy, parents | all present | The names were right; the axes were not |

What finally showed it was a quantity that spans BOTH rigs and cannot be
self-consistent: the toe-to-heel direction against the left-hip-minus-right-hip
direction. On a sound rig those are perpendicular. On the original's they
were the same axis — geometrically impossible for any pose, and therefore
data.

**When two rigs must agree, measure something that crosses between them.**
Anything relative to a rig's own hips will report that all is well.

## Derive nothing, measure everything

Two wrong answers here came from reasoning where a measurement was available:
which way to turn the rig, and what `SpineX` was for. Both were settled in
one probe each — print the hip axis, print the bone's height.

The same goes for judging the result. Screenshots were read wrong three times
running while the numbers were right there. Render the pair from ONE camera
with the driven rig stood on the source's hips (retargeting does not carry
the clip's displacement, so it stays at the origin and falls outside a frame
aimed at the source), show one mesh at a time, and let a person look.

## Verify against what the level actually loads

The `.import` route works and the one beside it does not, and only one of
them is what a chapter loads. `build_level.gd` reads a puppet's `.glb` with
`GLTFDocument` directly -- the extract directory is outside anything Godot
imports, and a level is built headless, where nothing is imported at all.
A body read that way carries the ORIGINAL's bone names (`Spine1`,
`LeftUpLeg`, `LeftToeBase`) and its own rest, so `RetargetModifier3D`
matches nothing and silently does nothing. No error, no warning, no change
on screen.

A retarget was implemented against a hand-configured copy of the same `.glb`
sitting under `assets/`, confirmed working, and shipped -- and did nothing
in the game, because the chapter loads the other one. **Load the asset the
way the level loads it before believing a retarget works**: print the first
few bone names and check one profile name (`Chest`, `LeftUpperArm`) is
among them.

Giving the levels that pipeline is real work: the humanoid rigs have to be
written somewhere stable rather than into the regenerable extract cache,
each needs an `.import` beside it, `--headless --import` has to run before
the build, and `_puppet_bodies()` has to `load()` the imported resource
instead of parsing the file.
