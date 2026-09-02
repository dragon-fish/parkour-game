class_name RoamingProps
extends Node3D

# TEMPORARY, for hand-testing the torus plain. Delete with VoidProbe once the
# tutorial has a level of its own.
#
# Scenery that travels with the player instead of being tiled. Each prop is
# recycled the moment it falls further behind than the view reaches, and comes
# back somewhere ahead of him.
#
# WHY NOT TILE COPIES OF A FIXED LAYOUT. That was tried and it is the wrong
# shape for this level. A wrap exists so the player can run forever, NOT so he
# can see infinite copies of a world -- and tiling drags a whole family of
# constraints in with it: sight has to stay inside the tiled area, the period
# has to divide the ground pattern's spacing so the tiling's phase survives a
# crossing, and the ring count has to be re-derived every time the view
# distance moves. None of those are properties of the wrap. They are
# properties of the scaffolding.
#
# With props that follow, the world in front of the player is always freshly
# placed, so there is nothing to compare across a seam and sight can go as far
# as it likes.

## The body props arrange themselves around.
@export var player: Player

## The level's wrap. Props MUST take the same step the body takes across a
## seam: the wrap moves the player a whole period while the world stands
## still, so anything not carried along lands a period away from where the
## player last saw it. A box that was fifty metres ahead is suddenly fifty
## metres behind, and the crossing announces itself.
@export var wrap: TorusWrap

## How many props to keep alive.
@export var count: int = 26

## Recycled once further from the player than this. Keep it comfortably past
## the camera's far plane, or the player watches props vanish.
@export var recycle_distance: float = 320.0

## Where a recycled prop reappears, as a distance from the player.
@export var place_min: float = 60.0
@export var place_max: float = 260.0

## Half-angle of the fan a prop is placed into, measured off the player's
## facing. A NEARLY FULL CIRCLE ON PURPOSE: props only ahead would leave the
## world visibly empty the moment the player turns round.
@export var place_fan_deg: float = 150.0

var _props: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if wrap != null:
		wrap.wrapped.connect(_on_wrapped)
	_rng.seed = 20260903
	for i in count:
		var prop := _build_prop(i)
		add_child(prop)
		_props.append(prop)
		_place(prop)

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var here: Vector3 = player.global_position
	for prop in _props:
		var away: Vector3 = prop.global_position - here
		away.y = 0.0
		if away.length() > recycle_distance:
			_place(prop)

## Carries every prop across the seam with the body, so their positions
## relative to it never change. Recycling happens afterwards, on distance, as
## usual -- this only preserves continuity through the teleport itself.
func _on_wrapped(offset: Vector3) -> void:
	for prop in _props:
		prop.global_position += offset

## Puts one prop somewhere around the player, at a random distance and bearing.
func _place(prop: Node3D) -> void:
	if player == null:
		return
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var bearing: float = deg_to_rad(_rng.randf_range(-place_fan_deg, place_fan_deg))
	var direction: Vector3 = facing.rotated(Vector3.UP, bearing)
	var distance: float = _rng.randf_range(place_min, place_max)
	var at: Vector3 = player.global_position + direction * distance
	prop.global_position = Vector3(at.x, prop.position.y, at.z)

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
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	return body
