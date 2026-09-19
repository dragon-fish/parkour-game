extends Node3D

# An extracted level's own look, applied to the Arena it is instanced in: the
# sun the lightmaps were baked from, a sky built for that sun, the original's
# haze as distance fog, and its default tone curves. Lives in the geometry
# scene, which is rebuilt freely, so a level's hand-edited shell never has to be.
#
# RUNTIME ONLY. In the editor it would write into the shell's Environment
# resource, which is shared with every level using the same preset.
#
# The original's world is lit by baked lightmaps (Beast) under one warm sun
# and a modest blue sky light, seen under a painted dome several times
# brighter than that light, exposed by a bounded auto exposure and graded by
# per-channel tone curves. What stands in for each here:
#   - the sun: a DirectionalLight3D along the baked light's direction, in its
#     colour, with hard long shadows; energy from its BakerBrightness.
#   - the dome: me_dome.gdshader on an inverted sphere that rides with the
#     camera, unlit and out of the fog. It lights nothing.
#   - the sky light: the Environment's sky (me_sky.gdshader), a plain
#     gradient in the bake's SkyLight colours at the share the bake gave it,
#     feeding the ambient and SDFGI. Godot has one sky for what is seen and
#     what lights; with the dome bright enough to look right, a street canyon
#     under it came out in daylight. SDFGI reads that sky whatever the
#     ambient settings say, so the split has to be two skies, not two dials.
#   - lamps: direct light only. SDFGI in these levels bounces none of it
#     (measured: a test lamp lit a corridor the same with SDFGI on and off,
#     on Vulkan and D3D12), so an interior is as bright as its lamps reach.
#   - exposure: fixed, normalised by the sun's brightness so a sunlit white
#     lands in the same place in every level; the original's auto exposure
#     would have settled there. From inside a doorway the street is white and
#     from the street the interior is black, as in the original.
#   - the haze: depth fog in the haze colour, reaching the haze distance, that
#     dissolves the far city into the sky (aerial perspective) instead of
#     drawing a wall.
#   - reflections from SDFGI alone: no screen-space reflection (its
#     screen-edge fade drew an oval of city on every large facade) and no sky
#     fallback (clouds on floors indoors).
#
# The data fields below come from the manifest (environment.py). The dials
# are judged against the owner's screenshots of the original
# (.private/docs/me-reference-shots) and are overridden per level from the
# level config's "look" block, by name.

const Lut := preload("res://tools/me_level/me_tone_curve.gd")
const SKY_SHADER := preload("res://tools/me_level/me_sky.gdshader")
const DOME_SHADER := preload("res://tools/me_level/me_dome.gdshader")
const CLOUD_PANORAMA := preload("res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr")
## Inside the camera's far plane (4000 m) and beyond every backdrop.
const DOME_RADIUS_M := 2500.0

# ---- data: the original's, read from its packages ----

## Unit vector toward the sun, Godot axes. [ME:CONFIRMED] the baked
## DirectionalLight's rotation, falling back to HazeSunLocation.
@export var sun_direction := Vector3.UP
## [ME:CONFIRMED] BakerColor and BakerBrightness of that light.
@export var sun_color := Color.WHITE
@export var sun_brightness := 1.0
## [ME:CONFIRMED] WorldInfo.SkyColor. Not the dome's painted colour (the
## tutorial's dome is a far deeper blue) and not yet used by the look;
## recorded because it is the one per-level sky datum the packages hold.
@export var sky_color := Color(0.3, 0.7, 1.0)
## [ME:CONFIRMED] the haze: colour, the distance it is normalised by, the
## exponent of distance, and its strength.
@export var haze_color := Color(1.0, 0.9, 0.6)
@export var haze_distance_m := 750.0
@export var haze_curve := 0.25
@export var haze_multiplier := 1.0
## The original's tone curves: x, y pairs per channel; A applies to all three.
@export var curve_r := PackedVector2Array()
@export var curve_g := PackedVector2Array()
@export var curve_b := PackedVector2Array()
@export var curve_a := PackedVector2Array()
@export var midtones := Vector3.ONE

# ---- dials ----

## Exposure, before the curves, of a sun of brightness 1. The level's exposure
## is this over its sun's brightness, times exposure_scale: a sunlit white
## then lands at the same value whatever the bake's units.
const EXPOSURE_PER_SUN := 0.85
@export var exposure_scale := 1.0
## Godot light energy per unit of BakerBrightness.
@export var sun_energy_scale := 1.0
## How much of the baked sun's colour the live sun keeps, 0 white to 1 all
## of it. The bake mixed its warm sun with a blue sky light into whites that
## read neutral; the live sun alone reads yellow at 1.
@export var sun_tint := 0.5
## Soft edge of the sun's shadows, degrees of sun disc. [ME:CONFIRMED] the
## bake's SoftShadowAngle is 2.0, but DO NOT raise this above 0: Godot's
## soft directional shadows (PCSS) let the sun through a roof 80 m above the
## camera, and the Stormdrain pillar hall was lit sand-yellow by a sun that
## never reaches it. Hard shadows, filtered by the project's shadow quality.
@export var sun_softness_deg := 0.0
## How far from the camera the sun still casts shadows, metres. The city's
## far blocks stand in each other's shadow in every overview shot.
@export var shadow_distance_m := 300.0
## The sky light, relative to a sun of brightness 1: its radiance from above
## and from below (the ground's bounce), and its colours. [ME:CONFIRMED] the
## tutorial bakes with a SkyLight of brightness 0.4 in (0.64, 0.70, 0.85) over
## a LowerBrightness 0.25 in (0.74, 0.63, 0.45), under a sun of 2.5.
## [ME:DERIVED] 0.4 / 2.5 = 0.16 and 0.25 / 2.5 = 0.1. The dome is a painting
## and owes the sky light nothing: it is not what lights the shadows.
@export var ambient_energy := 0.16
@export var ambient_color := Color(0.64, 0.70, 0.85)
@export var ambient_ground_energy := 0.1
@export var ambient_ground_color := Color(0.74, 0.63, 0.45)
## How much bounced light SDFGI adds, sun and lamps alike.
@export var bounce_energy := 1.0
## The dome's own brightness in the frame.
@export var sky_energy := 1.0
## The dome's colours, linear, at the brightness the frame should show them.
## Zenith is also the hue of every shadow.
@export var sky_zenith := Color(0.04, 0.09, 0.3)
@export var sky_horizon := Color(0.1, 0.22, 0.5)
@export var sky_ground := Color(0.3, 0.36, 0.5)
@export var sky_horizon_falloff := 0.6
@export var cloud_amount := 1.0
@export var cloud_yaw_deg := 0.0
## Bloom off the sunlit whites: the softness the original's screen has.
@export var glow_intensity := 0.3
@export var glow_bloom := 0.06
## Distance fog strength relative to the haze data; 0 turns the haze off.
@export var haze_strength := 1.0
## Where the haze starts, metres, and how it ramps toward the haze distance:
## a ramp above 1 keeps the near blocks clear and thickens toward the far
## city. [ME:UNKNOWN] how HazeDistanceCurve maps onto this; at 0.25 taken as
## Godot's depth curve the haze stood on the street in front of the camera.
@export var haze_start_m := 60.0
@export var haze_ramp := 1.6
## The haze tint is the haze colour pulled toward the dome's horizon: the
## far city dissolves into the sky it stands against, not into yellow.
@export var haze_sky_mix := 0.5
## The dome takes the same tint in a band above the horizon, so the sky the
## haze fades toward is a sky that has the haze in it.
@export var sky_haze_band := 0.35
## Contact shadow in corners (SSAO). The bake has it everywhere.
@export var ao_intensity := 1.5
## Volumetric fog density inside the volumetric range; 0 leaves it off.
## For interiors whose lamps should glow in the air (the Stormdrain halls).
@export var volumetric_density := 0.0
@export var volumetric_distance_m := 64.0

var _dome: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var arena := _arena()
	if arena == null:
		return
	var world := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment.duplicate()
		_apply_sky(env)
		_apply_light(env)
		_apply_post(env)
		world.environment = env
		# The base level's auto exposure would undo the fixed exposure above.
		world.camera_attributes = null
	_apply_haze(arena)
	_apply_sun(arena)
	_add_dome()


## The dome rides with the camera: what it shows depends on direction only.
func _process(_delta: float) -> void:
	if _dome == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_dome.global_position = camera.global_position


func _sky_parameters(material: ShaderMaterial, energy: float) -> void:
	material.set_shader_parameter("zenith_color", Vector3(sky_zenith.r, sky_zenith.g, sky_zenith.b))
	material.set_shader_parameter("horizon_color", Vector3(sky_horizon.r, sky_horizon.g, sky_horizon.b))
	material.set_shader_parameter("ground_color", Vector3(sky_ground.r, sky_ground.g, sky_ground.b))
	material.set_shader_parameter("horizon_falloff", sky_horizon_falloff)
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("cloud_panorama", CLOUD_PANORAMA)
	material.set_shader_parameter("cloud_amount", cloud_amount)
	material.set_shader_parameter("cloud_yaw", deg_to_rad(cloud_yaw_deg))
	material.set_shader_parameter("sun_glow_color", Vector3(haze_color.r, haze_color.g, haze_color.b))
	var haze := _haze_tint()
	material.set_shader_parameter("haze_band_color", Vector3(haze.r, haze.g, haze.b))
	material.set_shader_parameter("haze_band", 0.0)
	var tint := _sun_color()
	material.set_shader_parameter("sun_disc_color", Vector3(tint.r, tint.g, tint.b))


func _apply_sky(env: Environment) -> void:
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	# The sky light, not the dome: the bake's colours from above and below,
	# relative to the sun, so undoing the exposure keeps the share whatever
	# the sun is worth. No clouds, no glare.
	_sky_parameters(material, 1.0 / _exposure())
	var above := ambient_color * ambient_energy
	var below := ambient_ground_color * ambient_ground_energy
	material.set_shader_parameter("zenith_color", Vector3(above.r, above.g, above.b))
	material.set_shader_parameter("horizon_color", Vector3(above.r, above.g, above.b))
	material.set_shader_parameter("ground_color", Vector3(below.r, below.g, below.b))
	material.set_shader_parameter("cloud_amount", 0.0)
	material.set_shader_parameter("sun_glow_energy", 0.0)
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0


func _add_dome() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = DOME_RADIUS_M
	mesh.height = DOME_RADIUS_M * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.flip_faces = true
	var material := ShaderMaterial.new()
	material.shader = DOME_SHADER
	_sky_parameters(material, sky_energy / _exposure())
	material.set_shader_parameter("haze_band", sky_haze_band)
	material.set_shader_parameter("sun_direction", sun_direction.normalized())
	_dome = MeshInstance3D.new()
	_dome.name = "SkyDome"
	_dome.mesh = mesh
	_dome.material_override = material
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_dome.ignore_occlusion_culling = true
	_dome.extra_cull_margin = DOME_RADIUS_M
	_dome.top_level = true
	add_child(_dome)


func _apply_light(env: Environment) -> void:
	env.sdfgi_enabled = true
	# Eight cascades, not four: the reflections SDFGI gives end where its
	# cascades do, and at four that edge drew a sphere on every tower's
	# glass, city inside it and bare sky beyond.
	env.sdfgi_cascades = 8
	env.sdfgi_energy = bounce_energy
	env.sdfgi_read_sky_light = true
	env.ssr_enabled = false
	# Reflections from SDFGI only, never the sky directly: a sky fallback
	# put clouds on every glossy floor and wall indoors (the airlock's).
	# SDFGI covers the level and reflects the sky only where it is seen.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ssao_enabled = ao_intensity > 0.0
	env.ssao_intensity = ao_intensity
	env.ssao_radius = 1.0
	env.ssil_enabled = false


func _apply_post(env: Environment) -> void:
	# Linear, not AgX or Filmic: the original clips. From inside a doorway
	# its street is white, and its sunlit walls sit just under white with the
	# glow taking the edge off. A filmic curve rolled those whites down to
	# grey and desaturated the orange with them.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = _exposure()
	env.glow_enabled = glow_intensity > 0.0
	env.glow_intensity = glow_intensity
	env.glow_bloom = glow_bloom
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	env.adjustment_color_correction = Lut.texture(curve_r, curve_g, curve_b, curve_a, midtones)


## The haze as Arena's FogConfig, which Arena writes into the Environment
## every frame: setting the Environment directly would last one frame.
func _apply_haze(arena: Arena) -> void:
	if arena.fog == null:
		return
	var fog: FogConfig = arena.fog.duplicate()
	arena.fog = fog
	fog.enabled = haze_strength > 0.0 or volumetric_density > 0.0
	fog.fade_begin_distance = haze_start_m
	fog.fade_end_distance = haze_distance_m
	fog.max_opacity = clampf(haze_multiplier * haze_strength, 0.0, 1.0)
	fog.tint = _haze_tint()
	# No aerial perspective: the Environment's sky is the dim lighting sky,
	# and blending toward it darkened the far city instead of lifting it.
	fog.sky_blend = 0.0
	fog.sky_affect = 0.0
	fog.volumetric_enabled = volumetric_density > 0.0
	fog.volumetric_density = volumetric_density
	fog.volumetric_distance = volumetric_distance_m
	fog.volumetric_ambient_inject = 0.5
	var world := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		# Arena leaves the depth curve alone.
		world.environment.fog_depth_curve = maxf(haze_ramp, 0.05)


func _haze_tint() -> Color:
	return haze_color.lerp(sky_horizon, clampf(haze_sky_mix, 0.0, 1.0))


func _apply_sun(arena: Arena) -> void:
	var sun := arena.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null or sun_direction.length_squared() == 0.0:
		return
	var up := Vector3.UP if absf(sun_direction.normalized().y) < 0.99 else Vector3.FORWARD
	sun.global_basis = Basis.looking_at(-sun_direction.normalized(), up)
	sun.visible = true
	sun.light_color = _sun_color()
	sun.light_energy = sun_brightness * sun_energy_scale
	sun.light_angular_distance = sun_softness_deg
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = shadow_distance_m
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_fade_start = 0.9


func _sun_color() -> Color:
	return Color.WHITE.lerp(sun_color, clampf(sun_tint, 0.0, 1.0))


func _exposure() -> float:
	return EXPOSURE_PER_SUN / maxf(sun_brightness, 0.01) * exposure_scale


func _arena() -> Arena:
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	return node as Arena
