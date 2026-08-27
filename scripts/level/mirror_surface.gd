class_name MirrorSurface
extends Resource

# How dirty ONE mirror is. Owned by a Mirror node (`@export var surface`), and
# a plain Resource so a grimy-warehouse look can be saved once as a .tres and
# hung on every mirror in that level -- the same reason MovementConfig is one.
# The mirror must read as imperfect: thickness-driven refraction loss, slight
# random distortion, haze, and aging/grime are all deliberate, not bugs to
# clean up.
#
# THE DIRT IS NOT DECORATION, IT IS THE PERFORMANCE BUDGET. A mirror renders
# the scene a second time; the only way that stays affordable is rendering it
# small. What makes a half-resolution reflection unnoticeable is exactly this
# list -- displacement, wobble, haze, patchy silvering. DO NOT turn all of it
# to zero: the mirror then both looks like a hole in the wall AND needs full
# resolution to hold up. See Mirror.resolution_scale, which is the other half
# of the deal.
#
# Cracking is NOT here yet. It needs an authored crack mask rather than the
# procedural noise everything below uses, and a mirror that shatters on impact
# is the same system as breakable glass -- worth building once, together.

## Light the glass keeps. A colour rather than a scalar so a mirror can lean
## cold or warm as well as dim: silvering ages toward yellow-green, and a
## cheap modern mirror is faintly blue.
@export var reflectance: Color = Color(0.86, 0.88, 0.92)

## Glass thickness, in metres. A real mirror is silvered on the BACK face, so
## the image has crossed the pane twice and comes back displaced -- more so the
## further off-axis you look. 0 gives a front-silvered mirror with no
## displacement, which is the "perfect" look this exists to avoid.
@export_range(0.0, 0.06, 0.001) var thickness: float = 0.012

## How uneven the pane is: the slow wobble that makes a reflection breathe as
## you walk past. Float glass is never flat, and a reflection that holds
## perfectly still is the single strongest tell that it is a render.
@export_range(0.0, 1.0) var warp: float = 0.35
## Size of the unevenness. Low is long lazy waves; high is a rippled pane.
@export_range(0.5, 40.0) var warp_scale: float = 6.0

## Fog on the glass, 0 clear to 1 thick.
##
## Reads mostly as CONTRAST LOSS rather than blur, which is both truer to a
## fogged mirror and much cheaper -- Godot's ViewportTextures carry no mipmaps,
## so there is no free LOD to blur with (checked, not assumed).
@export_range(0.0, 1.0) var haze: float = 0.25
## What the haze lifts the image toward. Near the room's own light colour.
@export var haze_color: Color = Color(0.72, 0.76, 0.82)

## Age: patchy darkening and desaturation where the silvering has gone.
@export_range(0.0, 1.0) var grime: float = 0.30
## Size of the patches. Low is a few big blooms; high is fine speckle.
@export_range(0.5, 40.0) var grime_scale: float = 9.0

## How much the pane's own sheen takes over from the image at grazing angles.
@export_range(0.0, 1.0) var fresnel_strength: float = 0.25
## The surface's roughness before any grime is added on top.
@export_range(0.0, 1.0) var roughness: float = 0.06


## Writes every field onto the mirror's ShaderMaterial. One place, so a field
## added above cannot be silently left unapplied by one of two call sites.
func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("reflectance", reflectance)
	material.set_shader_parameter("thickness", thickness)
	material.set_shader_parameter("warp", warp)
	material.set_shader_parameter("warp_scale", warp_scale)
	material.set_shader_parameter("haze", haze)
	material.set_shader_parameter("haze_color", haze_color)
	material.set_shader_parameter("grime", grime)
	material.set_shader_parameter("grime_scale", grime_scale)
	material.set_shader_parameter("fresnel_strength", fresnel_strength)
	material.set_shader_parameter("roughness_amount", roughness)
