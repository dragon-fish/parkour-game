class_name RoamingProps
extends Node3D

# TEMPORARY, for hand-testing the torus plain. Delete with VoidProbe once the
# tutorial has a level of its own.
#
# Scenery that travels with the player. Four rules, and every one of them is
# about what the PLAYER sees rather than about how the wrap works:
#
#   ONE WORLD AT A TIME. Only ever one set of props is in view. Copies, if an
#   implementation uses them, are a convenience of the code and must never be
#   two things the player can see at once.
#
#   A PROP LEAVES BECAUSE IT LOOKS FAR AWAY, never because a seam was crossed.
#   recycle_distance therefore sits INSIDE the view, not beyond it: the player
#   is meant to watch a prop go, not to find it missing.
#
#   A PROP ARRIVES IN FRONT, along the way the player is actually travelling,
#   and near enough to be watched arriving. Not behind, not off-camera.
#
#   THE WRAP EXISTS ONLY SO THE RUNNING NEVER ENDS. It is not a way to show
#   the player copies of a world. So crossing a seam changes nothing he can
#   see: every prop takes the same step the body takes, and the relative
#   picture is untouched.
#
# The growth and collapse here are plain alpha, on purpose -- GrowingSolid owns
# the real timing contract for the tutorial's own obstacles, and this file is
# scaffolding that must not grow into a second implementation of it.

## The body props arrange themselves around.
@export var player: Player

## The level's wrap. Props MUST take the same step the body takes across a
## seam, or a prop that was fifty metres ahead becomes one fifty metres behind
## in a single frame -- the crossing announcing itself in the loudest way
## available.
@export var wrap: TorusWrap

## How many props to keep alive.
@export var count: int = 26

## A prop starts leaving once it is further than this. MUST be comfortably
## INSIDE the camera's far plane: the player is supposed to see it go.
@export var recycle_distance: float = 150.0

## Where a returning prop appears, as a distance from the player. Both ends
## inside the view, so arriving is something that happens on screen.
@export var place_min: float = 70.0
@export var place_max: float = 170.0

## Half-angle of the fan a returning prop is placed into, measured off the
## direction the player is TRAVELLING. Narrow, because the rule is "ahead of
## him", not "somewhere around him".
@export var place_fan_deg: float = 45.0

## The opening spread, used once. The world is already there when the player
## arrives, so the first set surrounds him instead of queueing up ahead.
@export var opening_fan_deg: float = 180.0

@export var grow_time: float = 0.9
@export var collapse_time: float = 0.9

enum Phase { GROWING, STANDING, LEAVING }

## One entry per prop. Named fields rather than parallel arrays because this
## grows: see naming-config-fields.
##   node   the prop's root
##   meshes its GeometryInstance3D children, gathered once
##   phase  Phase
##   at     seconds spent in the current phase
var _props: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if wrap != null:
		wrap.wrapped.connect(_on_wrapped)
	_rng.seed = 20260903
	for i in count:
		var node := _build_prop(i)
		add_child(node)
		var meshes: Array[GeometryInstance3D] = []
		for child in node.find_children("*", "GeometryInstance3D", true, false):
			meshes.append(child as GeometryInstance3D)
		var entry: Dictionary = {
			node = node,
			meshes = meshes,
			phase = Phase.STANDING,
			at = 0.0,
		}
		_props.append(entry)
		_place(entry, opening_fan_deg)
		_apply_alpha(entry, 1.0)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var here: Vector3 = player.global_position
	for entry in _props:
		match entry.phase:
			Phase.GROWING:
				entry.at += delta
				var k: float = clampf(entry.at / maxf(grow_time, 0.001), 0.0, 1.0)
				_apply_alpha(entry, k)
				if k >= 1.0:
					entry.phase = Phase.STANDING
			Phase.STANDING:
				var away: Vector3 = entry.node.global_position - here
				away.y = 0.0
				# DISTANCE, never the crossing. A prop leaves when it looks far
				# off; a teleport is not a reason for anything to leave.
				if away.length() > recycle_distance:
					entry.phase = Phase.LEAVING
					entry.at = 0.0
			Phase.LEAVING:
				entry.at += delta
				var k: float = clampf(entry.at / maxf(collapse_time, 0.001), 0.0, 1.0)
				_apply_alpha(entry, 1.0 - k)
				if k >= 1.0:
					_place(entry, place_fan_deg)
					entry.phase = Phase.GROWING
					entry.at = 0.0

## Carries every prop across the seam with the body, so the picture in front of
## the player is identical either side of it. Recycling still happens on
## distance afterwards, exactly as it would have without the crossing.
func _on_wrapped(offset: Vector3) -> void:
	for entry in _props:
		entry.node.global_position += offset

## The way the player is actually going. Travel rather than facing: he can be
## looking sideways while running forwards, and a prop should arrive where he
## is heading. Falls back to facing when he is too slow for travel to mean
## anything.
func _heading() -> Vector3:
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if travel.length() > 1.0:
		return travel.normalized()
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.001:
		return Vector3.FORWARD
	return facing.normalized()

func _place(entry: Dictionary, fan_deg: float) -> void:
	if player == null:
		return
	var bearing: float = deg_to_rad(_rng.randf_range(-fan_deg, fan_deg))
	var direction: Vector3 = _heading().rotated(Vector3.UP, bearing)
	var distance: float = _rng.randf_range(place_min, place_max)
	var at: Vector3 = player.global_position + direction * distance
	var node: Node3D = entry.node
	node.global_position = Vector3(at.x, node.position.y, at.z)
	_apply_alpha(entry, 0.0)

func _apply_alpha(entry: Dictionary, k: float) -> void:
	var shown: float = clampf(1.0 - k, 0.0, 1.0)
	for mesh in entry.meshes:
		mesh.transparency = shown

func _build_prop(index: int) -> StaticBody3D:
	# Sizes cycle rather than randomise, so the same seed always builds the
	# same set and two runs can be compared by eye.
	var sizes: Array[Vector3] = [
		Vector3(4.0, 3.0, 4.0),
		Vector3(2.0, 8.0, 2.0),
		Vector3(10.0, 1.2, 3.0),
		Vector3(3.0, 5.0, 3.0),
		Vector3(6.0, 2.0, 6.0),
	]
	var size: Vector3 = sizes[index % sizes.size()]

	var body := StaticBody3D.new()
	body.name = "Prop%d" % index
	body.position.y = size.y * 0.5

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.60, 0.68)
	# Transparency is what growth and collapse are made of here, so the
	# material has to be able to express it at all.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	return body
