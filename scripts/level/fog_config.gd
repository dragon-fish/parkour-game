class_name FogConfig
extends Resource

# What ONE level asks of its WorldEnvironment, atmosphere-wise. Owned by Arena
# (`@export var fog`), deliberately NOT a group on MovementConfig.
#
# Fog is a per-level dial, not a MovementConfig field, because a level may
# legitimately want a completely clear sky. MovementConfig is ONE object the
# player carries from level to level -- putting fog there would mean a foggy
# rooftop and a clear blue courtyard could never disagree.
# CameraConfig.ambient_cold_strength is the level concern that DID end up on
# the player side, and its own comment apologises for it at length; this is
# that mistake not repeated.
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
## Whether this level has any fog at all. Uncheck for a clear sky -- Arena turns
## BOTH fogs off at the Environment, so the level looks the same as one that
## never declared a FogConfig, without losing the values tuned below.
@export var enabled: bool = true

## How far from the camera the world starts fading out, in metres. Nearer than
## this, nothing is touched.
##
## THIS IS A CONTENT DIAL BEFORE IT IS AN ATMOSPHERE ONE -- it draws the
## curtain at whatever radius the level is actually built out to, so an
## unfinished ground or horizon (seen e.g. from a rooftop) stays hidden. A
## hand-built skyline pushes it away; a whitebox rooftop pulls it in.
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

## Colour of the depth fog, and so the colour the horizon turns.
##
## AUTHORITATIVE, up to whatever sky_blend below gives away. Set this white
## and the fog is white.
@export var tint: Color = Color(0.63, 0.72, 0.82)

## How much of `tint` is surrendered to the real sky colour behind the fog,
## 0 none and 1 all of it (Godot's Environment.fog_aerial_perspective). Turning
## it up makes distant ground dissolve INTO the sky instead of ending at a
## same-coloured-everywhere wall; turning it down makes `tint` mean exactly
## what it says.
##
## THIS DIAL CAN MAKE THE ONE ABOVE (tint) LOOK BROKEN, which is why it stays
## reachable from the same panel rather than being a hardcoded constant: a
## look value that overrules another look value has to be adjustable
## alongside it. The sky is an HDRI now (assets/sky/day_sky.tres), so what
## this blends toward is whatever that panorama shows in that direction --
## turn it UP, not off, to let the real sky colour through instead of a flat
## tint wall.
##
## Defaults to 0.25 rather than 0 for two reasons: white still reads white at
## that blend, and the F1 slider's range is 3× the default, so a dial that
## defaults to 0 gets a 0..0.01 slider nobody can move.
@export var sky_blend: float = 0.25

## How much the depth fog is allowed to swallow the SKY, 0 to 1.
##
## ZERO FOR AN ORDINARY LEVEL, and that is the default. The fog's job there is
## hiding unfinished GROUND; a fog that eats the sky as well turns a rooftop
## view into a flat white void, which is worse than the horizon it was sent to
## hide.
##
## ONE IS FOR A LEVEL THAT WANTS EXACTLY THAT VOID. Sky and ground arriving at
## the same value is what deletes a horizon, and a level built out of white
## needs the sky to stop being a separate thing behind the world. Turning this
## up is the way to get there WITHOUT swapping the shared sky resource -- the
## sky is still there, still lighting the scene and still being reflected in
## glossy surfaces; it is only its own image that the fog takes.
@export var sky_affect: float = 0.0

## Whether this level pays for the volumetric fog at all -- the froxel grid is
## per-frame work a level that only wants the far-fade curtain has no use for.
##
## OFF BY DEFAULT: DO NOT flip this true without deliberate intent.
## Volumetric fog fills the air EVERYWHERE inside volumetric_distance,
## including the metre in front of the camera -- turned on with Godot's own
## default density it reads as a uniform haze on the player's own face, not
## distant atmosphere.
##
## The two fogs' jobs were right in the docs and the defaults contradicted
## them: "clear nearby, thickening in the distance" is the DEPTH fog, and it
## already defaults to exactly that (60 m to 160 m). Volumetric fog exists for
## LIGHT SHAFTS -- without a strong light and something to occlude it, it is
## just soup. A light shaft is something a level asks for, not a tax every
## level pays.
##
## SEPARATE FROM volumetric_density, and it has to be. Godot's own docs give
## "set volumetric_fog_density to 0.0" as the way to make fog appear ONLY
## inside FogVolume nodes -- dust in the light shaft, clear air everywhere
## else. Fold the switch into the density and that setup becomes unreachable:
## the density reaches 0, the grid switches off, and every FogVolume in the
## level silently stops rendering with nothing to explain why.
@export var volumetric_enabled: bool = false

## Thickness of the volumetric fog EVERYWHERE, before any FogVolume adds to it.
## 0.0 is not "off" (see volumetric_enabled above) -- it is clear air that
## FogVolumes can still put dust into.
##
## Godot's own default (0.05) is kept as the default here so the F1 slider,
## whose range is RANGE_FACTOR × the default, spans 0..0.15 -- thin haze to
## thick enough that a shaft is unmistakable.
@export var volumetric_density: float = 0.05

## How far the volumetric fog reaches from the camera, in metres -- literally
## where "near" ends (Godot's Environment.volumetric_fog_length).
##
## KEEP THIS BELOW fade_begin_distance IF YOU WANT A CLEAN FAR CURTAIN. The
## two fogs are drawn independently and you see through BOTH: a white depth-fog
## curtain that begins at 30 m while the volumetric fog still reaches 64 m is a
## white wall viewed through 30 m of dim haze, and it reads grey no matter what
## `tint` says -- keeping the two ranges from overlapping is what keeps "distant
## white fog" and "near volumetric fog" as two separate effects instead of one
## grey smear. Nothing enforces it, because some levels DO want the two mixed.
##
## Shortening it also SHARPENS light shafts, free: the froxel grid is a fixed
## number of cells (rendering/environment/volumetric_fog/volume_size, 64) spread
## over this distance, so 30 m of fog is more than twice the detail of 64 m.
@export var volumetric_distance: float = 64.0

## How much of the level's ambient light reaches the volumetric fog, 0 to 1
## (Godot's Environment.volumetric_fog_ambient_inject).
##
## Volumetric fog is LIT fog, not coloured fog -- its colour is whatever light
## reaches each cell, times the albedo. Godot defaults this to 0, which means
## ambient contributes NOTHING and fog standing in shadow is not dim white but
## literally BLACK. That is where "the fog looks grey" comes from: white where
## the sun reaches it, black where it does not.
##
## Turn it UP for an even, luminous haze. Turn it DOWN for the strongest light
## shafts -- a shaft IS the contrast between lit and unlit fog, so lifting the
## unlit half flattens it. The two wants are opposed and this is where you pick.
##
## Defaults to 0.25 rather than Godot's 0 for the same two reasons sky_blend
## does: pitch-black shadowed fog is rarely what anyone means, and the F1
## slider's range is 3x the default, so a 0 default is a slider nobody can move.
@export var volumetric_ambient_inject: float = 0.25
