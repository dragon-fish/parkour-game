# The full animation libraries (optional, paid, not tracked)

The two `*_standard.glb` files beside this one are the **free** tiers of
Quaternius' Universal Animation Library: 43 clips each. They are tracked, and
the game runs on them alone.

The **full** tiers are 120 and 134 clips, and are where the parkour vocabulary
actually lives — `SafetyVault`, `WallRun_L/R`, `ClimbUp_2m`, the eight-way walk
and jog sets, and UAL1's whole ledge-climb chain. They are not in this
repository. Buying them yourself is the only supported route.

## Why they are not here

The licence on the files is **CC0 1.0** — a public domain dedication — so
redistributing them would be entirely legal, attribution not even required.
This is a deliberate choice not to. Quaternius sells these tiers to fund the
work, and mirroring the paid library in a public repository takes that apart
whatever the licence permits. (They are also ~42 MB of binary, which is its own
argument.)

## Getting them

1. Buy both packs from <https://quaternius.com/> (linked through to itch.io):
   - *Universal Animation Library* — the Pro or Source tier
   - *Universal Animation Library 2* — the Source tier

2. Out of each archive take `Unreal-Godot/UAL1.glb` and
   `Unreal-Godot/UAL2.glb`. **Not** the `_RM` twins — those have root motion
   baked into every clip, and this project drives every metre of travel from
   code. Using them makes the body move twice.

3. Put them here, with these names — `assets/animations/full/` is git-ignored:

   ```
   assets/animations/full/ual1_full.glb
   assets/animations/full/ual2_full.glb
   ```

4. Let Godot import them once, then add the retargeting block to **both**
   `.import` files, replacing the empty `_subresources={}` line:

   ```
   _subresources={
   "nodes": {
   "PATH:Armature/Skeleton3D": {
   "rest_pose/external_animation_library": null,
   "retarget/bone_map": Resource("res://assets/animations/ual2_bone_map.tres")
   }
   }
   }
   ```

   Without it the clips import against the pack's own 65-bone rig and drive
   nothing on a VRM. ⚠️ Editing a `.import` by hand does not trigger a
   reimport: delete `.godot/imported/ual1_full.glb-*` and
   `ual2_full.glb-*` afterwards, then reimport.

   The bone map is tracked and covers all 53 humanoid bones. The rig is
   identical across all four files, free and paid, so one map serves them all.

5. Point a body profile's `animation_libraries` at the two new files instead of
   the `*_standard.glb` pair. The free clips are a strict subset of the full
   ones, so nothing is lost by dropping them from the list.

## Running without them

Supported, and it does not break anything. Every list in
`CharacterAnimator._target_animation()` is a priority list resolved against the
clips the attached body actually has, so a missing `SafetyVault` falls through
to the take-off half of a jump exactly as it did before the packs were bought.
The moves are all still there; some of them just look like a placeholder.
