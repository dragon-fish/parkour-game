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

const WIRE_COLOR := Color(0.4, 0.85, 1.0, 0.35)

var _inside: Node3D = null
var _held: float = 0.0
var _fired := false


func _ready() -> void:
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
	_held += delta
	var prompt := UsePrompt.shared(get_tree())
	if _held < dwell:
		prompt.fill(_held / dwell)
		return
	_fired = true
	set_physics_process(false)
	prompt.complete()
	used.emit()


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
