class_name CapsuleDebug
extends Node3D

# Draws the player's collision capsule as wireframe, plus -- in third person --
# the three things that cannot be seen from inside the head: where the feet are,
# where the first-person eye would be, and what it would be looking at.
#
# The capsule folding and the body's ride height over an obstacle are two
# separate, unrelated facts, and both can be true at once even though a folded
# capsule mid-vault still looks like a whole person clearing the top -- nothing
# on screen could tell the two apart before this existed.
#
# What set_capsule_height() does is move the collision shape DOWN by half the
# difference and shorten it, so the FEET stay exactly where they were and only
# the head comes down. The visible model is placed from a transform captured at
# attach, so it does not move either -- test_clip_offsets.gd asserts that on
# purpose, because a body that sank whenever the capsule did would be showing a
# crouch it was not performing.
#
# So folding is real, and it does nothing to how high the body rides over an
# obstacle. That is the ARC, and a different number.
#
# Drawn as an ImmediateMesh rather than a CapsuleMesh with a wireframe material:
# wireframe in Godot 4 is a shader render mode, not a BaseMaterial3D flag, and
# an ImmediateMesh needs no shader to maintain.

@export var player: Player

@export_group("Capsule")
## Rings around the barrel, plus one at each cap.
@export var rings: int = 5
@export var segments: int = 24
@export var capsule_colour := Color(0.2, 1.0, 0.4)

@export_group("Third person extras")
## The sole plane, drawn as a filled disc. This is the surface that answers
## "standing on the ledge or floating over it".
@export var sole_colour := Color(1.0, 0.85, 0.2, 0.35)
@export var sole_scale: float = 1.6
## Where the eye WOULD be in first person -- which is the rig's own origin, the
## camera child being the thing that pulls back for third person.
@export var eye_colour := Color(0.4, 0.8, 1.0, 0.9)
@export var frustum_colour := Color(0.4, 0.8, 1.0, 0.12)
@export var frustum_distance: float = 1.5

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _lines: StandardMaterial3D
var _fill: StandardMaterial3D
var _shown := false
var _last_height: float = 0.0

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	# Everything below is described in WORLD space every frame, so the instance
	# must not add a transform of its own.
	_instance.top_level = true
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# NO material_override: that would apply one material to every surface, and
	# the fills have to be transparent where the lines must not be. ImmediateMesh
	# takes a material per surface instead.
	_lines = StandardMaterial3D.new()
	_lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines.vertex_color_use_as_albedo = true
	# Through walls, since in first person the inside of the body is the only
	# place the capsule is ever seen from.
	_lines.no_depth_test = true
	_lines.render_priority = 2
	_fill = StandardMaterial3D.new()
	_fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill.vertex_color_use_as_albedo = true
	_fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# BOTH SIDES. A sole disc seen from below and a frustum seen from outside are
	# both back-faces, and culling them leaves the debug view empty from exactly
	# the angles it is most useful at.
	_fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill.no_depth_test = true
	_fill.render_priority = 1
	add_child(_instance)
	_instance.visible = false
	# So the tuning panel's Debug page can find this overlay by name and
	# duck-type show_overlay()/overlay_shown() on it, without either side
	# knowing about the other's class.
	add_to_group("debug_overlay")

## Turns the outline on or off from code.
##
## The animation lab opens with it ON: that scene should show only what helps
## reading a take, and the capsule and curve are exactly that. In a level it
## stays off until F10, because there it is one of several things worth a key;
## in the lab it is half of what the scene is FOR.
func show_overlay(on: bool) -> void:
	_shown = on
	if _instance != null:
		_instance.visible = on

## Duck-typed getter the tuning panel's Debug page reads every frame to keep
## its checkbox in sync with a keyboard toggle (F10).
func overlay_shown() -> bool:
	return _shown

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F10:
		_shown = not _shown
		_instance.visible = _shown

func height() -> float:
	return _last_height

func _process(_delta: float) -> void:
	if not _shown or player == null:
		return
	var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return
	_last_height = capsule.height
	_mesh.clear_surfaces()
	var at: Transform3D = shape_node.global_transform
	# DO NOT read the sole position off the folded capsule's own bottom
	# transform, even though the two coincide today: set_capsule_height()
	# (player.gd) keeps the capsule's bottom pinned to the standing sole by
	# construction, but an earlier build anchored the capsule at the top
	# instead, which put this marker a half-body too high with no error to
	# catch it. Deriving the sole independently from standing_height() keeps
	# this debug view honest even if that guarantee ever changes again.
	var sole: float = player.global_position.y - player.standing_height() * 0.5
	_draw_capsule(at, capsule.radius, capsule.height)
	# ONLY IN THIRD PERSON. From inside the head the eye marker is in your face
	# and the frustum is the thing you are looking through, so neither says
	# anything. The rig is the authority on which view is running.
	var rig = player.camera_rig
	if rig != null and rig.third_person:
		_draw_fills(capsule.radius, sole, rig)

# --- the capsule ----------------------------------------------------------------

## A capsule is a cylinder with two hemispherical caps, and its `height` is the
## WHOLE thing -- so the cylinder is height - 2 * radius tall. Getting this
## wrong draws a capsule that is right in the middle and wrong at both ends,
## which is where the interesting part is.
func _draw_capsule(at: Transform3D, radius: float, total: float) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lines)
	_mesh.surface_set_color(capsule_colour)
	var barrel: float = maxf(total - radius * 2.0, 0.0)
	var top: float = barrel * 0.5
	var bottom: float = -barrel * 0.5
	for i in rings:
		var t: float = float(i) / float(maxi(rings - 1, 1))
		_ring(at, radius, lerpf(bottom, top, t))
	_arc(at, radius, top, 1.0, Vector3.RIGHT)
	_arc(at, radius, top, 1.0, Vector3.FORWARD)
	_arc(at, radius, bottom, -1.0, Vector3.RIGHT)
	_arc(at, radius, bottom, -1.0, Vector3.FORWARD)
	# Verticals down the barrel, which is what makes the height readable at a
	# glance.
	for i in 4:
		var angle: float = TAU * float(i) / 4.0
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_line(at * (offset + Vector3.UP * bottom), at * (offset + Vector3.UP * top))
	_mesh.surface_end()

# --- what the head cannot see ----------------------------------------------------

func _draw_fills(radius: float, sole_y: float, rig) -> void:
	var sole_centre := Vector3(player.global_position.x, sole_y, player.global_position.z)
	# THE EYE IS THE RIG'S OWN ORIGIN. The Camera3D child is what pulls back for
	# third person, so the rig itself stays where the first-person view would be
	# -- head-follow offset and all, since that is written onto the rig too.
	var eye: Vector3 = rig.global_position
	var basis: Basis = rig.camera.global_transform.basis if rig.camera != null \
			else rig.global_transform.basis

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill)
	_disc(sole_centre, radius * sole_scale, sole_colour)
	if rig.camera != null:
		_frustum(eye, basis, rig.camera.fov, frustum_colour)
	_mesh.surface_end()

	# The eye's own outline and the plumb line down to the soles, so the height
	# between them is a thing you can read rather than estimate.
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lines)
	_mesh.surface_set_color(eye_colour)
	_ring(Transform3D(Basis.IDENTITY, eye), 0.07, 0.0)
	_line(eye, Vector3(eye.x, sole_centre.y, eye.z))
	_line(Vector3(eye.x - 0.15, sole_centre.y, eye.z),
			Vector3(eye.x + 0.15, sole_centre.y, eye.z))
	_mesh.surface_end()

func _disc(centre: Vector3, radius: float, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		var b: float = TAU * float(i + 1) / float(segments)
		_tri(centre,
				centre + Vector3(cos(a) * radius, 0.0, sin(a) * radius),
				centre + Vector3(cos(b) * radius, 0.0, sin(b) * radius))

## The four side faces of the view pyramid, apex at the eye. `fov` is VERTICAL
## in Godot's default keep_aspect, so the horizontal half-angle comes from the
## viewport's own ratio rather than from a second field.
func _frustum(apex: Vector3, basis: Basis, fov_degrees: float, colour: Color) -> void:
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = size.x / maxf(size.y, 1.0)
	var half_h: float = tan(deg_to_rad(fov_degrees) * 0.5) * frustum_distance
	var half_w: float = half_h * aspect
	var centre: Vector3 = apex + forward * frustum_distance
	var corners: Array[Vector3] = [
		centre - right * half_w - up * half_h,
		centre + right * half_w - up * half_h,
		centre + right * half_w + up * half_h,
		centre - right * half_w + up * half_h,
	]
	_mesh.surface_set_color(colour)
	for i in 4:
		_tri(apex, corners[i], corners[(i + 1) % 4])

# --- primitives -------------------------------------------------------------------

func _ring(at: Transform3D, radius: float, y: float) -> void:
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		var b: float = TAU * float(i + 1) / float(segments)
		_line(at * Vector3(cos(a) * radius, y, sin(a) * radius),
				at * Vector3(cos(b) * radius, y, sin(b) * radius))

## Half a ring in the vertical plane containing `axis`, bulging by `sign_y`.
func _arc(at: Transform3D, radius: float, y: float, sign_y: float, axis: Vector3) -> void:
	var steps: int = segments / 2
	for i in steps:
		var a: float = PI * float(i) / float(steps)
		var b: float = PI * float(i + 1) / float(steps)
		_line(at * (axis * (cos(a) * radius) + Vector3.UP * (y + sin(a) * radius * sign_y)),
				at * (axis * (cos(b) * radius) + Vector3.UP * (y + sin(b) * radius * sign_y)))

func _line(a: Vector3, b: Vector3) -> void:
	_mesh.surface_add_vertex(a)
	_mesh.surface_add_vertex(b)

func _tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	_mesh.surface_add_vertex(a)
	_mesh.surface_add_vertex(b)
	_mesh.surface_add_vertex(c)
