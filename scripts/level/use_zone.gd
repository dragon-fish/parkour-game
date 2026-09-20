class_name UseZone
extends Area3D

## Where the original had a "use" button: this project has no use key, so
## standing in the zone for `dwell` seconds counts as pressing it. Fires once
## per visit -- step out and back in to use it again, which is how a lever
## that goes up and down gets pulled twice.
##
## Drawn as a translucent wireframe of its own shapes, and reported to the
## UsePrompt ring by the crosshair while it fills.

signal used

@export var dwell: float = 1.0
## The dwell only counts while the whole capsule is inside the zone's boxes.
## A lift car: counting from the first touch at the door, the car left
## before the player was in it.
@export var require_whole_body: bool = false

const WIRE_COLOR := Color(0.4, 0.85, 1.0, 0.35)

var _inside: Node3D = null
var _held: float = 0.0
var _fired := false


func _ready() -> void:
	# Only the body, never the level it stands in -- see Arena.PLAYER_LAYER.
	collision_mask = Arena.PLAYER_LAYER
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_physics_process(false)
	_build_wireframe()


func _on_body_entered(body: Node3D) -> void:
	# Duck-typed like Checkpoint: whatever can touch a checkpoint is a player.
	if not body.has_method("touch_checkpoint"):
		return
	_inside = body
	_held = 0.0
	_fired = false
	set_physics_process(true)


func _on_body_exited(body: Node3D) -> void:
	if body != _inside:
		return
	_inside = null
	set_physics_process(false)
	if not _fired:
		UsePrompt.shared(get_tree()).abandon()


func _physics_process(delta: float) -> void:
	if _inside == null or _fired:
		set_physics_process(false)
		return
	var prompt := UsePrompt.shared(get_tree())
	if require_whole_body and not _holds_whole(_inside):
		_held = 0.0
		prompt.fill(0.0)
		return
	_held += delta
	if _held < dwell:
		prompt.fill(_held / dwell)
		return
	_fired = true
	set_physics_process(false)
	prompt.complete()
	used.emit()


## Whether every extreme of the body's capsule is inside one of this zone's
## boxes. Other shapes never hold a whole body.
func _holds_whole(body: Node3D) -> bool:
	var capsule: CapsuleShape3D = null
	var at := Transform3D()
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			capsule = (child as CollisionShape3D).shape
			at = (child as CollisionShape3D).global_transform
			break
	if capsule == null:
		return true
	var r := capsule.radius
	var h := capsule.height * 0.5
	var extremes: Array[Vector3] = [Vector3(0, h, 0), Vector3(0, -h, 0)]
	for side: Vector3 in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		extremes.append(side)
	for child in get_children():
		if not (child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D):
			continue
		var box := AABB(-(child.shape as BoxShape3D).size * 0.5, (child.shape as BoxShape3D).size)
		var to_local: Transform3D = (child as CollisionShape3D).global_transform.affine_inverse()
		if extremes.all(func(e: Vector3) -> bool: return box.grow(0.01).has_point(to_local * (at * e))):
			return true
	return false


## One line mesh per collision shape: the hull's edges, or a cylinder's rings.
## Runtime-built presentation only; the zone itself is the saved shapes.
func _build_wireframe() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = WIRE_COLOR
	for child in get_children():
		if not child is CollisionShape3D:
			continue
		var shape: Shape3D = (child as CollisionShape3D).shape
		var points := PackedVector3Array()
		if shape is ConvexPolygonShape3D:
			points = shape.get_debug_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		elif shape is CylinderShape3D:
			var c := shape as CylinderShape3D
			for y in [-c.height * 0.5, c.height * 0.5]:
				for k in 32:
					var a0 := TAU * k / 32.0
					var a1 := TAU * (k + 1) / 32.0
					points.append(Vector3(cos(a0) * c.radius, y, sin(a0) * c.radius))
					points.append(Vector3(cos(a1) * c.radius, y, sin(a1) * c.radius))
			for k in 8:
				var a := TAU * k / 8.0
				points.append(Vector3(cos(a) * c.radius, -c.height * 0.5, sin(a) * c.radius))
				points.append(Vector3(cos(a) * c.radius, c.height * 0.5, sin(a) * c.radius))
		if points.is_empty():
			continue
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		for p in points:
			mesh.surface_add_vertex(p)
		mesh.surface_end()
		var instance := MeshInstance3D.new()
		instance.name = "Wireframe"
		instance.mesh = mesh
		instance.transform = (child as CollisionShape3D).transform
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance, false, Node.INTERNAL_MODE_BACK)
