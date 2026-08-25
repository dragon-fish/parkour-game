@tool
extends EditorNode3DGizmoPlugin

# The respawn preview, as a REAL gizmo: a translucent capsule at the player's
# own size plus a -Z arrow, with collision segments so clicking any of its
# lines selects the node in the viewport -- exactly what Marker3D's own gizmo
# provides and what runtime-built preview meshes never could (they have no
# owner, so the editor's selection ray refuses to see them).
#
# The two semantics are drawn honestly, same as before: a Checkpoint respawns
# FEET at the origin (capsule stands ON the node), a SpawnPoint carries the
# older centre-at-origin convention (capsule hangs 0.9 m below the marker).

const RADIUS := 0.3
const HEIGHT := 1.8
const SEGMENTS := 24

var _capsule_mesh: CapsuleMesh
var _fills: Dictionary = {}

func _init() -> void:
	create_material("checkpoint", Color(0.2, 0.9, 0.4))
	create_material("spawn", Color(0.75, 0.4, 1.0))
	create_handle_material("handles")
	_capsule_mesh = CapsuleMesh.new()
	_capsule_mesh.radius = RADIUS
	_capsule_mesh.height = HEIGHT
	# The translucent body fill -- the lines carry the clicking, this
	# carries the "a body stands here" read the mesh preview used to give.
	for entry in [["checkpoint", Color(0.2, 0.9, 0.4, 0.25)],
			["spawn", Color(0.75, 0.4, 1.0, 0.25)]]:
		var fill := StandardMaterial3D.new()
		fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fill.albedo_color = entry[1]
		_fills[entry[0]] = fill

func _get_gizmo_name() -> String:
	return "RespawnPoints"

func _has_gizmo(node: Node3D) -> bool:
	return node is Checkpoint or node is SpawnPoint

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node: Node3D = gizmo.get_node_3d()
	var checkpoint: bool = node is Checkpoint
	var bottom: float = 0.0 if checkpoint else -HEIGHT * 0.5
	var lines: PackedVector3Array = _capsule_lines(bottom)
	lines.append_array(_arrow_lines(bottom))
	var material: StandardMaterial3D = get_material(
		"checkpoint" if checkpoint else "spawn", gizmo)
	gizmo.add_lines(lines, material)
	gizmo.add_mesh(_capsule_mesh, _fills["checkpoint" if checkpoint else "spawn"],
		Transform3D(Basis(), Vector3(0.0, bottom + HEIGHT * 0.5, 0.0)))
	# THE POINT OF THE EXERCISE: these make the drawing clickable.
	gizmo.add_collision_segments(lines)
	# The yaw handle, riding the arrow's tip: drag it around the node and
	# the facing follows, no gizmo-mode switching.
	gizmo.add_handles(PackedVector3Array([Vector3(0.0, bottom + 1.0, -0.95)]),
		get_material("handles", gizmo), PackedInt32Array())

## Wireframe capsule standing on local y = `bottom`: two rings at the
## cylinder's ends, four verticals, and two perpendicular end-cap arcs.
func _capsule_lines(bottom: float) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var y0: float = bottom + RADIUS
	var y1: float = bottom + HEIGHT - RADIUS
	for i in SEGMENTS:
		var a: float = TAU * i / SEGMENTS
		var b: float = TAU * (i + 1) / SEGMENTS
		var pa := Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		var pb := Vector3(cos(b) * RADIUS, 0.0, sin(b) * RADIUS)
		lines.append(pa + Vector3.UP * y0)
		lines.append(pb + Vector3.UP * y0)
		lines.append(pa + Vector3.UP * y1)
		lines.append(pb + Vector3.UP * y1)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var side := Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		lines.append(side + Vector3.UP * y0)
		lines.append(side + Vector3.UP * y1)
	# End-cap arcs in the XY and ZY planes, top and bottom.
	for plane in [Vector3.RIGHT, Vector3.BACK]:
		for i in SEGMENTS / 2:
			var a: float = PI * i / (SEGMENTS / 2)
			var b: float = PI * (i + 1) / (SEGMENTS / 2)
			lines.append(plane * cos(a) * RADIUS + Vector3.UP * (y1 + sin(a) * RADIUS))
			lines.append(plane * cos(b) * RADIUS + Vector3.UP * (y1 + sin(b) * RADIUS))
			lines.append(plane * cos(a) * RADIUS + Vector3.UP * (y0 - sin(a) * RADIUS))
			lines.append(plane * cos(b) * RADIUS + Vector3.UP * (y0 - sin(b) * RADIUS))
	return lines

## The facing arrow at chest height, pointing down -Z -- where the respawned
## body wakes up looking.
func _arrow_lines(bottom: float) -> PackedVector3Array:
	var chest: float = bottom + 1.0
	var lines := PackedVector3Array()
	lines.append(Vector3(0.0, chest, -RADIUS))
	lines.append(Vector3(0.0, chest, -0.95))
	for wing in [Vector3(0.12, 0.0, -0.75), Vector3(-0.12, 0.0, -0.75),
			Vector3(0.0, 0.12, -0.75), Vector3(0.0, -0.12, -0.75)]:
		lines.append(Vector3(0.0, chest, -0.95))
		lines.append(wing + Vector3.UP * chest)
	return lines

# --- the yaw handle --------------------------------------------------------

func _get_handle_name(_gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> String:
	return "yaw"

func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().global_rotation

func _set_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool,
		camera: Camera3D, screen_pos: Vector2) -> void:
	var node: Node3D = gizmo.get_node_3d()
	var chest: float = 1.0 if node is Checkpoint else 1.0 - HEIGHT * 0.5
	# The drag lives on the horizontal plane the arrow sits in: wherever the
	# mouse ray crosses it, that is where the arrow should point.
	var plane := Plane(Vector3.UP, node.global_position.y + chest)
	var hit: Variant = plane.intersects_ray(
		camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	var d: Vector3 = hit - node.global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	# -Z is the facing: with yaw t the node's -Z runs (-sin t, 0, -cos t).
	node.global_rotation.y = atan2(-d.x, -d.z)

func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool,
		restore: Variant, cancel: bool) -> void:
	var node: Node3D = gizmo.get_node_3d()
	if cancel:
		node.global_rotation = restore
		return
	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	ur.create_action("Rotate respawn point")
	ur.add_do_property(node, "global_rotation", node.global_rotation)
	ur.add_undo_property(node, "global_rotation", restore)
	ur.commit_action()
