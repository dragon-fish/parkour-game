class_name CapsuleDebug
extends Node3D

# Draws the player's collision capsule as wireframe, live.
#
# ✅ The owner, after the vault was made to fold its capsule: "has it actually
# folded? during a vault the character still looks a whole person above the top
# of the obstacle." Both halves of that are true at once, and the capsule was
# the only way to tell them apart -- which is why this exists.
#
# What set_capsule_height() does is move the collision shape DOWN by half the
# difference and shorten it, so the FEET stay exactly where they were and only
# the head comes down. The visible model is mounted from a transform captured at
# attach time, so it does not move either -- test_clip_offsets.gd asserts that
# on purpose, because a body that sank whenever the capsule did would be showing
# a crouch it was not performing.
#
# So folding is real, and it does nothing whatsoever to how high the body rides
# over an obstacle. That is the ARC's doing, and a different number.
#
# Drawn as lines rather than a CapsuleMesh with a wireframe material: wireframe
# in Godot 4 is a shader render mode, not a BaseMaterial3D flag, and an
# ImmediateMesh needs no shader to maintain.

@export var player: Player
## Rings around the barrel, plus one at each cap.
@export var rings: int = 5
@export var segments: int = 24
@export var colour := Color(0.2, 1.0, 0.4)
## Drawn through everything, so the capsule is visible from inside the body --
## which in first person is the only place it is ever seen from.
@export var through_walls: bool = true

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _material: StandardMaterial3D
var _shown := false
## What the capsule measured last time it was drawn, so the readout can say
## whether it changed rather than only what it is.
var _last_height: float = 0.0

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	# The capsule is described in WORLD space every frame, so the instance must
	# not add a transform of its own.
	_instance.top_level = true
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = colour
	_material.no_depth_test = through_walls
	_material.render_priority = 1
	_instance.material_override = _material
	add_child(_instance)
	_instance.visible = false

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
	_draw(shape_node.global_transform, capsule.radius, capsule.height)

## A capsule is a cylinder with two hemispherical caps, and its `height` is the
## WHOLE thing -- so the cylinder is height - 2 * radius tall and the centres of
## the caps sit that far apart. Getting this wrong draws a capsule that is right
## in the middle and wrong at both ends, which is where the interesting part is.
func _draw(at: Transform3D, radius: float, total: float) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(colour)
	var barrel: float = maxf(total - radius * 2.0, 0.0)
	var top: float = barrel * 0.5
	var bottom: float = -barrel * 0.5

	for i in rings:
		var t: float = float(i) / float(maxi(rings - 1, 1))
		_ring(at, radius, lerpf(bottom, top, t))
	# The caps, as half-rings in two planes each, so the ends read as domes
	# rather than as flat lids.
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
	# THE FEET, as a cross at the very bottom of the capsule. This is the line
	# that answers "is the body standing on the ledge or floating over it".
	var sole: float = bottom - radius
	_line(at * Vector3(-radius * 1.5, sole, 0.0), at * Vector3(radius * 1.5, sole, 0.0))
	_line(at * Vector3(0.0, sole, -radius * 1.5), at * Vector3(0.0, sole, radius * 1.5))
	_mesh.surface_end()

func _ring(at: Transform3D, radius: float, y: float) -> void:
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		var b: float = TAU * float(i + 1) / float(segments)
		_line(at * Vector3(cos(a) * radius, y, sin(a) * radius),
				at * Vector3(cos(b) * radius, y, sin(b) * radius))

## Half a ring in the vertical plane containing `axis`, bulging by `sign`.
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
