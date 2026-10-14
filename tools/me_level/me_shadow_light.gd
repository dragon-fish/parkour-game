@tool
extends DirectionalLight3D

# The player's shadow on a lightmapped level: the original's DynamicLightEnvironment
# modulated shadow. The baked world takes no live light (me_lightmap.gdshaderinc);
# this light only takes light away from it, where the player's body blocks it.
#
# [ME:CONFIRMED MirrorsEdge.exe DLE 0xff4690, 0xff4517, 0x106e8c0; Engine/Shaders/
# ModShadowProjectionPixelShader.usf, ModShadowCommon.usf] what the original does:
#   - the pawn's light environment gathers a SHADOW environment, an SH of every
#     light that has bCastCompositeShadow (the sun, the sky light), each times
#     its visibility from the pawn's bounds centre (one trace), plus
#     AmbientShadowColor from AmbientShadowSourceDirection, which the pawn
#     itself keeps pointing (Player.ambient_shadow_source_direction);
#   - its dominant lobe d (the SH's band 1) places a point light at
#     LightDistance bounds radii along d; the shadow reaches Radius =
#     R * (LightDistance + ShadowDistance + 2) from it;
#   - ModShadowColor = A / (A + L): L the dominant lobe's intensity, A the
#     ambient left over once it is taken out. A lone sun gives black;
#   - a receiver is multiplied by 1 - (1 - Lit^2) * Att * Fade * (1 - Mod),
#     Att = (1 - dist^2 / Radius^2) ^ ShadowFalloffExponent from the light, Fade
#     the shadow's resolution fade. Everything in the frustum receives it:
#     BSP, lightmapped meshes, the caster itself; no backface culling (the
#     pawn's mode is LightShadow_Modulate, not ModulateBetter).
#
# What stands in here: a directional light along -d, of NEGATIVE energy (which
# me_lightmap.gdshaderinc reads as "this is the shadow light"), coloured
# 1 - ModShadowColor, at energy -Fade; Att is evaluated per texel from
# me_shadow_light_sphere (a shader global: the point light's position and
# 1 / Radius; its ShadowFalloffExponent is the shader's). [ME:INFERRED] the perspective of the original's point light at
# 8 radii is dropped: its shadow is about an eighth larger than this one.
#
# Only BAKED_LAYER receives it and only CHARACTER_SHADOW_LAYER casts into it
# (me_level_common.gd). That layer is put on the player's casting meshes here,
# at runtime, on every update -- a body mounted or split later is tagged too --
# and only on those on neither of the first/third-person body layers: those
# are drawn in both views already, so one more layer bit cannot show them in
# the wrong one. They are what casts in first person as well ([ME:CONFIRMED
# TdGame.u] the original's third-person mesh has bOwnerNoSeeWithShadow:
# unseen, still casting; HeadlessVariant's shadow stand-ins do the same here).
#
# RUNTIME ONLY beyond the built pose: in the editor it points along the sun
# and darkens nothing, nothing it lights being able to cast into it until a
# body is in the scene.

const Common := preload("res://tools/me_level/me_level_common.gd")
const SPHERE_GLOBAL := &"me_shadow_light_sphere"
## [ME:CONFIRMED DLE 0xf44e70] a directional light's TraceDistance, 100000 uu.
const TRACE_M := 1000.0

## [ME:CONFIRMED TdGame.u Default__TdPawn.MyLightEnvironment] in bounds radii.
@export var light_distance := 8.0
## [ME:CONFIRMED Engine DynamicLightEnvironmentComponent default] in bounds radii.
@export var shadow_distance := 1.0
## [ME:CONFIRMED DLE class defaults] AmbientShadowColor, linear. Where it
## comes from is the pawn's (_ambient_source_direction()).
@export var ambient_shadow_color := Vector3(0.15, 0.15, 0.15)
## [ME:CONFIRMED DLE class default] MinTimeBetweenFullUpdates, seconds.
@export var update_interval_s := 0.3
## The level's suns as a pawn's light environment sees them (environment.py
## character_shadow_lights): unit vectors toward each, Godot axes, their
## intensity, linear (Brightness * LightColor ^ 2.2, not the bake's), and
## whether each is traced from the pawn (CastShadows and CastStaticShadows).
@export var sun_directions := PackedVector3Array()
@export var sun_intensities := PackedVector3Array()
@export var sun_traced: Array[bool] = []
## The level's sky lights, summed, linear: Brightness * LightColor from above
## and LowerBrightness * LowerColor from below.
@export var sky_upper := Vector3.ZERO
@export var sky_lower := Vector3.ZERO
## [ME:INFERRED] the owner's bounds radius, metres: the original's are its
## mesh's bounds; the nearest held here is the collider, the original's own
## extent 0.6 x 1.8 x 0.6, whose half diagonal this is.
@export var bounds_radius := 0.995
## [ME:CONFIRMED owner's TdEngine.ini] the shadow resolution fade: MinShadowResolution,
## MaxShadowResolution, ShadowTexelsPerPixel, ModShadowFadeDistanceExponent.
@export var min_resolution := 32.0
@export var max_resolution := 1024.0
@export var texels_per_pixel := 2.0
@export var fade_exponent := 0.2

var _current := []
var _target := []
var _next_update := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_current = _empty_sh()
	_target = _empty_sh()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		RenderingServer.global_shader_parameter_set(SPHERE_GLOBAL, Vector4.ZERO)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := _player()
	if player == null:
		visible = false
		RenderingServer.global_shader_parameter_set(SPHERE_GLOBAL, Vector4.ZERO)
		return
	var centre: Vector3 = player.global_position
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_update:
		_tag_casters(player)
		_target = shadow_environment(_sun_visibility(centre), _ambient_source_direction(player))
		var camera := get_viewport().get_camera_3d()
		var distance := camera.global_position.distance_to(centre) if camera != null else 0.0
		_next_update = now + update_interval_s * randf_range(0.8, 1.2) \
				* clampf(distance / (2.0 * bounds_radius), 1.0, 10.0)
	# [ME:CONFIRMED DLE 0xff29d0] the environment glides toward the target,
	# arriving as the next update is due.
	var fade := clampf(delta / maxf(_next_update - now, 1e-5), 0.0, 1.0)
	for i in 9:
		_current[i] = (_current[i] as Vector3).lerp(_target[i], fade)
	var shadow := representative_shadow(_current)
	if shadow.is_empty():
		visible = false
		RenderingServer.global_shader_parameter_set(SPHERE_GLOBAL, Vector4.ZERO)
		return
	var to_light: Vector3 = shadow.direction
	var up := Vector3.UP if absf(to_light.y) < 0.99 else Vector3.FORWARD
	global_basis = Basis.looking_at(-to_light, up)
	var modulation: Vector3 = shadow.modulation
	light_color = Color(1.0 - modulation.x, 1.0 - modulation.y, 1.0 - modulation.z).linear_to_srgb()
	light_energy = -_resolution_fade(centre)
	visible = true
	var light_position := centre + to_light * bounds_radius * light_distance
	var radius := bounds_radius * (light_distance + shadow_distance + 2.0)
	RenderingServer.global_shader_parameter_set(SPHERE_GLOBAL,
			Vector4(light_position.x, light_position.y, light_position.z, 1.0 / radius))


## The shadow environment's SH: [9 x Vector3], linear RGB per coefficient.
## `visible` says, per sun, whether it reaches the pawn; `ambient_direction`
## is AmbientShadowSourceDirection, toward its source, Godot axes. Its class
## default is straight up.
func shadow_environment(visible: Array, ambient_direction := Vector3.UP) -> Array:
	var out := _empty_sh()
	for i in sun_directions.size():
		if i < visible.size() and visible[i]:
			_add_lobe(out, sun_directions[i].normalized(), sun_intensities[i])
	_add_lobe(out, ambient_direction.normalized(), ambient_shadow_color)
	# [ME:CONFIRMED DLE 0xff2310] each hemisphere's DC and z terms; untraced.
	out[0] += (sky_upper + sky_lower) * 0.5641896
	out[2] += (sky_upper - sky_lower) * 0.4886025
	return out


## [ME:CONFIRMED DLE 0xff4517-0xff45cc] the dominant lobe of a shadow
## environment and the shadow colour it leaves: {direction (toward the light,
## Godot axes), modulation (linear)}, or {} when there is no lobe.
static func representative_shadow(sh: Array) -> Dictionary:
	var lum := []
	for i in 9:
		var c: Vector3 = sh[i]
		lum.append(c.x * 0.3 + c.y * 0.59 + c.z * 0.11)
	var d_ue := Vector3(-lum[3], -lum[1], lum[2])
	if d_ue.length_squared() < 1e-12:
		return {}
	d_ue = d_ue.normalized()
	var basis := sh_basis(d_ue)
	var norm := 0.0
	for i in 9:
		norm += basis[i] * basis[i]
	var dominant := Vector3.ZERO
	for ch in 3:
		var dot := 0.0
		for i in 9:
			dot += (sh[i] as Vector3)[ch] * basis[i]
		dominant[ch] = maxf(0.0, dot / norm)
	if dominant.x <= 0.0 and dominant.y <= 0.0 and dominant.z <= 0.0:
		return {}
	var modulation := Vector3.ZERO
	for ch in 3:
		var ambient := maxf(0.0, ((sh[0] as Vector3)[ch] - dominant[ch] * basis[0]) / 0.2820948)
		modulation[ch] = minf(ambient / maxf(ambient + dominant[ch], 1e-5), 1.0)
	return {direction = _from_ue(d_ue), modulation = modulation}


## UE3's SH basis, 9 terms, of a unit vector in a z-up frame.
static func sh_basis(v: Vector3) -> PackedFloat32Array:
	return PackedFloat32Array([
		0.282095,
		-0.488603 * v.y,
		0.488603 * v.z,
		-0.488603 * v.x,
		1.092548 * v.x * v.y,
		-1.092548 * v.y * v.z,
		0.315392 * (3.0 * v.z * v.z - 1.0),
		-1.092548 * v.x * v.z,
		0.546274 * (v.x * v.x - v.y * v.y),
	])


## Godot (y up) to a z-up frame and back; a rotation, so the SH's dot products
## are the same in either.
static func _to_ue(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


static func _from_ue(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


static func _add_lobe(sh: Array, direction: Vector3, intensity: Vector3) -> void:
	var basis := sh_basis(_to_ue(direction))
	for i in 9:
		sh[i] += intensity * basis[i]


static func _empty_sh() -> Array:
	var out := []
	for i in 9:
		out.append(Vector3.ZERO)
	return out


## [ME:CONFIRMED DLE 0xff11e0: NumVolumeVisibilitySamples 1, from the bounds
## centre] Which suns reach the pawn: one trace each, 100000 uu long, against
## what casts shadows (Common.SUN_OCCLUDER_LAYER), not against what the pawn
## collides with; an untraced sun always does.
func _sun_visibility(centre: Vector3) -> Array:
	var space := get_world_3d().direct_space_state
	var out := []
	for i in sun_directions.size():
		if i < sun_traced.size() and not sun_traced[i]:
			out.append(true)
			continue
		var query := PhysicsRayQueryParameters3D.create(centre, centre + sun_directions[i].normalized() * TRACE_M,
				Common.SUN_OCCLUDER_LAYER)
		out.append(space.intersect_ray(query).is_empty())
	return out


## AmbientShadowSourceDirection as the pawn sets it. [ME:CONFIRMED TdGame.u
## TdPlayerPawn.Tick, TdMove_Grab] it moves with her: out of the sun her
## shadow falls a little ahead of her, and onto the wall she stands against
## or hangs from. A body that keeps none is lit from above.
static func _ambient_source_direction(player: Node) -> Vector3:
	var direction = player.get("ambient_shadow_source_direction")
	if direction is Vector3 and (direction as Vector3).length_squared() > 1e-8:
		return direction
	return Vector3.UP


## [ME:CONFIRMED 0x106e8c0] the shadow fades with the resolution its caster
## would get on screen: ((Res - Min) / (Max - Min)) ^ ModShadowFadeDistanceExponent,
## Res = clamp(ShadowTexelsPerPixel * screen radius in pixels, Min, Max - 10).
func _resolution_fade(centre: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 1.0
	var distance := maxf(camera.global_position.distance_to(centre), 0.01)
	# Camera3D.fov is the vertical one (KEEP_HEIGHT): half the height over its
	# tangent is the same scale as the original's half width over the
	# horizontal one.
	var half_height := get_viewport().get_visible_rect().size.y * 0.5
	var screen_radius := bounds_radius * half_height / tan(deg_to_rad(camera.fov) * 0.5) / distance
	var resolution := clampf(texels_per_pixel * screen_radius, min_resolution, max_resolution - 10.0)
	return pow((resolution - min_resolution) / maxf(max_resolution - min_resolution, 1.0), fade_exponent)


func _tag_casters(player: Node3D) -> void:
	var swapped := 0
	var config = player.get("config")
	if config != null:
		swapped = config.camera.first_person_body_layers | config.camera.third_person_body_layers
	for node in player.find_children("*", "GeometryInstance3D", true, false):
		var instance := node as GeometryInstance3D
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and instance.layers & swapped == 0:
			instance.layers |= Common.CHARACTER_SHADOW_LAYER


func _player() -> Node3D:
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	if node == null:
		return null
	return (node as Arena).player as Node3D
