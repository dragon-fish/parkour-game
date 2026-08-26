class_name Mirror
extends Node3D

# A real mirror: the scene rendered a second time from the eye's reflection,
# then dirtied on the way to the glass.
#
# ✅ THE OWNER: "我们能不能做真正的镜子?" -- really, not a ReflectionProbe and
# not screen-space reflections. Both were considered and neither can show you
# YOURSELF: SSR only has the pixels already on screen, and your front is not
# one of them; a probe is a cubemap of roughly-what's-around, not a
# geometrically correct image.
#
# EVERYTHING IS BUILT IN _ready(). Place the node, set `size`, done -- the
# SubViewport, its camera and the quad are plumbing nobody should have to wire
# by hand. Same call the InterestLine nodes make about their collision volume.
#
# FACING: the mirror looks along its own -Z, matching Checkpoint and the
# ladders. "Align Rotation with View" from where the player would stand,
# facing the mirror, places it correctly.
#
# ⚠️ WHAT IS BEHIND A MIRROR OCCLUDES IT. The reflection camera stands behind
# the mirror plane, so a wall the mirror hangs on sits between that camera and
# everything it is supposed to see. The textbook fix is an oblique near plane
# clipped to the mirror surface, and GODOT 4.7 CANNOT DO IT: Camera3D offers
# perspective / orthogonal / off-axis frustum and no custom projection matrix,
# and RenderingServer's camera_set_* are the same three (checked, not assumed).
# So the tool here is `reflection_cull_mask` -- put the wall behind a mirror on
# a layer this mask clears. That knob is doing double duty as the performance
# gate anyway, which is the only reason this is a fair trade rather than a
# workaround.

## The glass, in metres: width by height.
@export var size: Vector2 = Vector2(1.6, 2.4):
	set(value):
		size = value
		if _quad != null:
			_quad.mesh.size = size

## How dirty this mirror is. Leave null for a fresh MirrorSurface at defaults --
## which is still not a perfect mirror, deliberately. See mirror_surface.gd.
@export var surface: MirrorSurface

## The reflection's render size, as a fraction of the real viewport.
##
## ⚠️ THE SINGLE BIGGEST COST CONTROL HERE, and the reason the dirt exists.
## A mirror renders the whole scene again; at 0.5 it renders a quarter of the
## pixels. Warp, haze and grime hide that completely -- turn them all off and
## this has to come back up to 1.0 to stop looking soft.
@export_range(0.1, 1.0, 0.05) var resolution_scale: float = 0.5

## What the reflection is allowed to see, before the body layers below are
## folded in. Clear a layer here to keep it out of the mirror: the wall the
## mirror hangs on (see this file's header), distant scenery nobody will study
## in a reflection, decorative clutter. Every bit cleared is scene the second
## render does not pay for.
@export_flags_3d_render var reflection_cull_mask: int = 0xFFFFF

## The layer the mirror's own glass lives on, and the one layer the reflection
## camera is ALWAYS denied.
##
## Without this a mirror renders itself, from inside its own reflection,
## forever. Layer 20 by default because nothing else in this project uses the
## high layers; change it only if something does.
@export_flags_3d_render var mirror_layer: int = 1 << 19

## Metres beyond the glass before the reflection camera starts drawing. Small,
## because its only job is keeping the mirror's own plane out of the image --
## the wall behind it is `reflection_cull_mask`'s problem, NOT this one. An
## oblique near plane would solve both at once and Godot cannot express one.
const REFLECTION_NEAR := 0.05

var _quad: MeshInstance3D
var _viewport: SubViewport
var _reflection_camera: Camera3D
var _material: ShaderMaterial
var _notifier: VisibleOnScreenNotifier3D
var _on_screen: bool = true
## Cached so a resize is one comparison per frame rather than a resize per frame.
var _last_target_size := Vector2i.ZERO


## The whole of the reflection maths, and the only part worth asserting.
##
## Static and free of any node so a test can hand it two transforms and check
## the answer instead of instantiating a viewport. Godot's own reflection
## helpers are not used because Vector3.reflect() reflects ABOUT a normal
## rather than across the plane it defines -- a sign difference that would be
## invisible until something looked wrong on screen.
static func reflect_across(eye: Transform3D, plane: Plane) -> Transform3D:
	var normal := plane.normal
	var position := eye.origin - 2.0 * plane.distance_to(eye.origin) * normal
	var forward := _mirror_vector(-eye.basis.z, normal)
	var up := _mirror_vector(eye.basis.y, normal)
	# Rebuilt through looking_at rather than by reflecting all three axes: a
	# reflected basis is LEFT-handed (determinant -1), which flips triangle
	# winding and makes every surface in the mirror render inside-out.
	# looking_at gives a right-handed basis pointing the same way, and the
	# left-right flip a real mirror shows survives it -- it lives in the
	# reflected forward, not in the handedness.
	if absf(forward.normalized().dot(up.normalized())) > 0.999:
		up = _mirror_vector(eye.basis.x, normal)
	return Transform3D(Basis.looking_at(forward, up), position)

static func _mirror_vector(v: Vector3, normal: Vector3) -> Vector3:
	return v - 2.0 * v.dot(normal) * normal


## The plane this mirror's glass lies in, facing the side it is aimed at.
func plane() -> Plane:
	var normal := -global_transform.basis.z
	return Plane(normal, global_position)


func _ready() -> void:
	if surface == null:
		surface = MirrorSurface.new()
	_build_viewport()
	_build_quad()
	surface.apply_to(_material)
	# DEFERRED, and it has to be: Godot readies children before parents, so an
	# Arena's `config` is still null while its Mirror is readying -- the mask
	# would silently come out without the body-layer half and the reflection
	# would show a headless player. TuningPanel defers its own build for the
	# same reason and says so; this is that trap, hit a second time.
	_apply_cull_mask.call_deferred()


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Reflection"
	# The reflection is only correct while it is being redrawn from the current
	# eye, so it is ALWAYS while on screen and DISABLED the moment it is not --
	# a mirror facing away costs nothing at all. UPDATE_WHEN_VISIBLE watches the
	# SubViewport's own visibility, which is always true here; what actually
	# matters is whether the GLASS is on screen, and only the notifier knows.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = false
	add_child(_viewport)

	_reflection_camera = Camera3D.new()
	_reflection_camera.name = "ReflectionCamera"
	_reflection_camera.near = REFLECTION_NEAR
	# The reflection camera is driven every frame from the real one and must
	# never be the viewport's own "current" camera in the usual sense; it is
	# current only inside its own SubViewport, which is exactly right.
	_reflection_camera.current = true
	_viewport.add_child(_reflection_camera)


func _build_quad() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/mirror.gdshader")
	_material.set_shader_parameter("reflection_tex", _viewport.get_texture())

	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = _material

	_quad = MeshInstance3D.new()
	_quad.name = "Glass"
	_quad.mesh = mesh
	# QuadMesh faces +Z; this node's front is -Z (the Checkpoint convention),
	# so the glass turns to meet it.
	_quad.rotation.y = PI
	# The one layer the reflection camera is denied -- see mirror_layer.
	_quad.layers = mirror_layer
	# A mirror is a flat pane of glass. Its shadow would be a hard black
	# rectangle with nothing casting it, which reads as a bug every time.
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)

	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.name = "OnScreen"
	_notifier.aabb = AABB(Vector3(-size.x * 0.5, -size.y * 0.5, -0.05), Vector3(size.x, size.y, 0.1))
	_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(_notifier)


## The reflection sees the world, plus the body variant that HAS a head, minus
## the mirror's own glass.
##
## The body layers are read off the player's own CameraConfig rather than
## hardcoded, and folded in the same way CameraRig._apply_body_layers folds
## them: SHOW the third-person meshes, HIDE the first-person ones. That is what
## makes a player in first person see their whole self in the mirror instead of
## a decapitated body -- the single most obvious thing a mirror could get
## wrong. Walking up the tree for the Player mirrors what HeadlessVariant does
## for the same information.
func _apply_cull_mask() -> void:
	var mask := reflection_cull_mask & ~mirror_layer
	var camera_config := _find_camera_config()
	if camera_config != null:
		mask = (mask | camera_config.third_person_body_layers) \
			& ~camera_config.first_person_body_layers
	_reflection_camera.cull_mask = mask


func _find_camera_config() -> CameraConfig:
	var node: Node = get_parent()
	while node != null:
		# Duck-typed rather than `is Player`: a mirror dropped into a scene with
		# no player at all (a showcase, a test) must simply skip this, not fail.
		if node.get("config") != null and node.config is MovementConfig:
			return (node.config as MovementConfig).camera
		node = node.get_parent()
	var players := get_tree().get_nodes_in_group("player")
	for player in players:
		if player.get("config") != null and player.config is MovementConfig:
			return (player.config as MovementConfig).camera
	return null


func _process(_delta: float) -> void:
	if _viewport == null:
		return
	if not _on_screen:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var eye := get_viewport().get_camera_3d()
	if eye == null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_match_projection(eye)
	_reflection_camera.global_transform = reflect_across(eye.global_transform, plane())
	# Re-applied every frame for the same reason every other tunable in this
	# project is: dragging a value in the inspector while the game runs has to
	# change what is on screen now.
	if surface != null:
		surface.apply_to(_material)


## Keeps the reflection framed exactly like the real view, which is the whole
## reason the shader can sample it at plain SCREEN_UV.
func _match_projection(eye: Camera3D) -> void:
	_reflection_camera.fov = eye.fov
	_reflection_camera.keep_aspect = eye.keep_aspect
	_reflection_camera.far = eye.far
	var target := Vector2i(Vector2(get_viewport().get_visible_rect().size) * resolution_scale)
	target = target.max(Vector2i(64, 64))
	if target != _last_target_size:
		_last_target_size = target
		_viewport.size = target
