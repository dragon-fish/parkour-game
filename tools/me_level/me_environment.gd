extends Node3D

# An extracted level's own look, applied to the Arena it is instanced in: the
# sun where the original's haze puts it, the sky as the only ambient light, and
# the original's default tone curves. Lives in the geometry scene, which is
# rebuilt freely, so a level's hand-edited shell never has to be.
#
# RUNTIME ONLY. In the editor it would write into the shell's Environment
# resource, which is shared with every level using the same preset.
#
# The original's world is lit by baked lightmaps (Beast); its tone curves were
# graded on those. What stands in for them here:
#   - ambient from the sky through SDFGI, so an interior is dark and a sunlit
#     street is not: a flat ambient lit the Stormdrain pillar hall grey.
#   - reflections from SDFGI alone: no screen-space reflection (its
#     screen-edge fade drew an oval of city on every large facade) and no sky
#     fallback (clouds on floors indoors).
#   - fixed exposure: from inside a doorway the original's street is white and
#     from the street its interior is black.

const Lut := preload("res://tools/me_level/me_tone_curve.gd")

## Unit vector toward the sun, Godot axes.
@export var sun_direction := Vector3.UP
## The original's tone curves: x, y pairs per channel; A applies to all three.
@export var curve_r := PackedVector2Array()
@export var curve_g := PackedVector2Array()
@export var curve_b := PackedVector2Array()
@export var curve_a := PackedVector2Array()
@export var midtones := Vector3.ONE

## Linear exposure ahead of the tone curves. A dial, judged against the owner's
## screenshots of the original.
const EXPOSURE := 0.75


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var arena := _arena()
	if arena == null:
		return
	var world := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment.duplicate()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 1.0
		env.sdfgi_enabled = true
		# Eight cascades, not four: the reflections SDFGI gives end where its
		# cascades do, and at four that edge drew a sphere on every tower's
		# glass, city inside it and bare sky beyond.
		env.sdfgi_cascades = 8
		env.ssr_enabled = false
		# Reflections from SDFGI only, never the sky directly: a sky fallback
		# put clouds on every glossy floor and wall indoors (the airlock's).
		# SDFGI covers the level and reflects the sky only where it is seen.
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = EXPOSURE
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.0
		env.adjustment_saturation = 1.0
		env.adjustment_color_correction = Lut.texture(curve_r, curve_g, curve_b, curve_a, midtones)
		world.environment = env
		world.camera_attributes = null
	# Arena drives the fog from its FogConfig every frame: switch it there.
	if arena.fog != null:
		arena.fog = arena.fog.duplicate()
		arena.fog.enabled = false
	var sun := arena.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null and sun_direction.length_squared() > 0.0:
		var up := Vector3.UP if absf(sun_direction.normalized().y) < 0.99 else Vector3.FORWARD
		sun.global_basis = Basis.looking_at(-sun_direction.normalized(), up)
		sun.shadow_enabled = true


func _arena() -> Arena:
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	return node as Arena
