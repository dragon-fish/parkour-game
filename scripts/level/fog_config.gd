class_name FogConfig
extends Resource

# What ONE level asks of its WorldEnvironment, atmosphere-wise. Owned by Arena
# (`@export var fog`), deliberately NOT a group on MovementConfig.
#
# ✅ THE OWNER: "关卡可以通过参数调整这一关到底开不开fog以及开多少，因为万一有
# 关卡就是想要晴空万里呢?" MovementConfig is ONE object the player carries from
# level to level -- putting fog there would mean a foggy rooftop and a clear
# blue courtyard could never disagree. CameraConfig.ambient_cold_strength is
# the level concern that DID end up on the player side, and its own comment
# apologises for it at length; this is that mistake not repeated.
#
# TWO UNRELATED EFFECTS LIVE HERE because Godot draws them with two unrelated
# systems, and each can do a job the other cannot:
#
#   fade_* / max_opacity / tint  ->  Environment's DEPTH fog. Cheap, unbounded
#       range, no interaction with light at all. This is the one that hides an
#       unfinished horizon.
#   volumetric_density           ->  Environment's VOLUMETRIC fog. Voxelised,
#       reaches only Environment.volumetric_fog_length (64 m, left at Godot's
#       default) from the camera, and is the only one the sun can carve light
#       shafts out of -- and the only one a body walking through a beam can
#       cast a hole in.
#
# Neither substitutes for the other, which is why they are two dials and not
# one "fog amount".
#
# Both need the Forward+ renderer. The project runs on it (project.godot
# leaves rendering_method unset, which IS forward_plus; the "GL Compatibility"
# string in config/features is stale metadata that decides nothing), the same
# way the WorldEnvironment's existing ssr_enabled already depends on it.

## Whether this level has any fog at all. Uncheck for 晴空万里 -- Arena turns
## BOTH fogs off at the Environment, so the level looks the same as one that
## never declared a FogConfig, without losing the values tuned below.
@export var enabled: bool = true

## How far from the camera the world starts fading out, in metres. Nearer than
## this, nothing is touched.
##
## ✅ THE OWNER: "如果场景距离角色超过60米左右就开始淡出，避免从楼顶看到并没有
## 精心打磨的地面或远景." So this is a CONTENT dial before it is an atmosphere
## one -- it draws the curtain at whatever radius the level is actually built
## out to. A hand-built skyline pushes it away; a whitebox rooftop pulls it in.
@export var fade_begin_distance: float = 60.0

## How far from the camera the world has faded out completely, in metres.
##
## A SECOND DIAL RATHER THAN A MULTIPLE OF THE FIRST. How soft the curtain
## reads is judged by standing on a roof and looking, and the answer is not a
## constant times where the fade began: begin 60 / end 160 is a long gentle
## haze, begin 60 / end 65 is a wall. Both get wanted, so both ends get a knob.
##
## Nothing forbids dragging this below fade_begin_distance. Arena clamps the
## span to a hair above zero rather than crashing or silently reordering the
## two -- the result is that hard wall, which is the honest thing to show
## someone who is mid-drag.
@export var fade_end_distance: float = 160.0

## How completely the fog has swallowed the world at fade_end_distance:
## 1.0 nothing left to see, lower values leave a silhouette showing through.
##
## THIS DIAL IS NOT OPTIONAL EVEN THOUGH IT SOUNDS LIKE A REFINEMENT. Godot's
## Environment.fog_density means "maximum intensity of the deep fog" in
## FOG_MODE_DEPTH and ships defaulted to 0.01 -- set the distances but not
## this, and the fog is a 1%-opaque film that looks exactly like no fog. Arena
## clamps it to 0..1.
@export var max_opacity: float = 1.0

## Colour of the depth fog, and so the colour the horizon turns. Reads best
## near the sky's own horizon colour, which is what makes distant ground
## dissolve INTO the sky instead of ending at a visible grey wall; Arena also
## blends it toward the real sky colour (see Arena.FOG_AERIAL_PERSPECTIVE).
@export var tint: Color = Color(0.63, 0.72, 0.82)

## Thickness of the volumetric fog -- the one that produces light shafts.
## 0.0 switches it off entirely, which is the setting for a level that wants
## the far-fade curtain without paying for the froxel grid every frame.
##
## Godot's own default (0.05) is kept as the default here so the F1 slider,
## whose range is RANGE_FACTOR × the default, spans 0..0.15 -- thin haze to
## thick enough that a shaft is unmistakable.
@export var volumetric_density: float = 0.05
