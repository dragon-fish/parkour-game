@tool
extends EditorNode3DGizmoPlugin

# Level-marker gizmos: the respawn preview, and the interest-line family.
#
# The respawn preview, as a REAL gizmo: a translucent capsule at the player's
# own size plus a -Z arrow, with collision segments so clicking any of its
# lines selects the node in the viewport -- exactly what Marker3D's own gizmo
# provides and what runtime-built preview meshes never could (they have no
# owner, so the editor's selection ray refuses to see them).
#
# Both nodes share one semantic: origin = BODY CENTRE (✅ the owner chose
# consistency over a feet-at-origin checkpoint variant), so one geometry
# serves both and only the colour tells them apart.

const RADIUS := 0.3
const HEIGHT := 1.8
const SEGMENTS := 24

var _capsule_mesh: CapsuleMesh
var _shaft_mesh: CylinderMesh
var _head_mesh: CylinderMesh
var _fills: Dictionary = {}
var _arrows: Dictionary = {}

## Per-kind line colours: cyan cable, orange bar, yellow beam, red ladder.
const KIND_COLORS := {
	InterestLine.Kind.ZIPLINE: Color(0.3, 0.8, 1.0),
	InterestLine.Kind.SWING: Color(1.0, 0.6, 0.2),
	InterestLine.Kind.BALANCE: Color(0.95, 0.85, 0.2),
	InterestLine.Kind.LADDER: Color(0.95, 0.35, 0.35),
}

func _init() -> void:
	create_material("checkpoint", Color(0.2, 0.9, 0.4))
	create_material("spawn", Color(0.75, 0.4, 1.0))
	for kind in KIND_COLORS:
		create_material("line_%d" % kind, KIND_COLORS[kind])
	create_handle_material("handles")
	_capsule_mesh = CapsuleMesh.new()
	_capsule_mesh.radius = RADIUS
	_capsule_mesh.height = HEIGHT
	_shaft_mesh = CylinderMesh.new()
	_shaft_mesh.top_radius = 0.04
	_shaft_mesh.bottom_radius = 0.04
	_shaft_mesh.height = 0.5
	_head_mesh = CylinderMesh.new()
	_head_mesh.top_radius = 0.0
	_head_mesh.bottom_radius = 0.12
	_head_mesh.height = 0.25
	# The translucent body fill -- the lines carry the clicking, this
	# carries the "a body stands here" read the mesh preview used to give.
	for entry in [["checkpoint", Color(0.2, 0.9, 0.4, 0.25)],
			["spawn", Color(0.75, 0.4, 1.0, 0.25)]]:
		var fill := StandardMaterial3D.new()
		fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fill.albedo_color = entry[1]
		_fills[entry[0]] = fill
		var solid := StandardMaterial3D.new()
		solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		solid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		solid.albedo_color = Color(entry[1], 0.55)
		_arrows[entry[0]] = solid

func _get_gizmo_name() -> String:
	return "RespawnPoints"

func _has_gizmo(node: Node3D) -> bool:
	return node is Checkpoint or node is SpawnPoint or node is InterestLine

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node: Node3D = gizmo.get_node_3d()
	if node is InterestLine:
		_redraw_interest_line(gizmo, node)
		return
	var checkpoint: bool = node is Checkpoint
	var bottom: float = -HEIGHT * 0.5
	var lines: PackedVector3Array = _capsule_lines(bottom)
	lines.append_array(_arrow_lines(bottom))
	var material: StandardMaterial3D = get_material(
		"checkpoint" if checkpoint else "spawn", gizmo)
	gizmo.add_lines(lines, material)
	var key: String = "checkpoint" if checkpoint else "spawn"
	gizmo.add_mesh(_capsule_mesh, _fills[key], Transform3D(Basis(), Vector3.ZERO))
	# The arrow as SOLID meshes -- ✅ the owner: as bare lines it was nearly
	# invisible. Cylinders grow along +Y; tipped -90 about X to lie on -Z.
	var tip := Basis(Vector3.RIGHT, -PI * 0.5)
	var chest: float = bottom + 1.0
	gizmo.add_mesh(_shaft_mesh, _arrows[key],
		Transform3D(tip, Vector3(0.0, chest, -0.55)))
	gizmo.add_mesh(_head_mesh, _arrows[key],
		Transform3D(tip, Vector3(0.0, chest, -0.925)))
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
	var chest: float = 1.0 - HEIGHT * 0.5
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

# --- interest lines --------------------------------------------------------

## The runtime builds the reach volume and the rope only in the game, so in
## the editor a line was a bare Path3D curve nobody could read -- ✅ the
## owner: "在编辑器里好难看懂." Drawn per kind: the axis polyline, reach-radius
## rings, and for a LADDER the rungs plus a front arrow (the -Z side is the
## one thing an author keeps getting backwards).
func _redraw_interest_line(gizmo: EditorNode3DGizmo, line: InterestLine) -> void:
	if line.curve == null or line.curve.point_count < 2:
		return
	var material: StandardMaterial3D = get_material("line_%d" % line.kind, gizmo)
	var points: PackedVector3Array = line.curve.get_baked_points()
	var lines := PackedVector3Array()
	for i in range(points.size() - 1):
		lines.append(points[i])
		lines.append(points[i + 1])
	# Reach rings roughly every metre, oriented across the local tangent.
	var length: float = line.curve.get_baked_length()
	var step: float = maxf(length / maxf(floorf(length), 1.0), 0.5)
	var s: float = 0.0
	while s <= length + 0.01:
		var at: Vector3 = line.curve.sample_baked(minf(s, length))
		var ahead: Vector3 = line.curve.sample_baked(minf(s + 0.05, length))
		var behind: Vector3 = line.curve.sample_baked(maxf(s - 0.05, 0.0))
		var tangent: Vector3 = (ahead - behind).normalized()
		if tangent.length_squared() < 0.5:
			tangent = Vector3.UP
		var helper: Vector3 = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x: Vector3 = helper.cross(tangent).normalized() * line.reach_radius
		var z: Vector3 = tangent.cross(x).normalized() * line.reach_radius
		for i in 12:
			var a: float = TAU * i / 12.0
			var b: float = TAU * (i + 1) / 12.0
			lines.append(at + x * cos(a) + z * sin(a))
			lines.append(at + x * cos(b) + z * sin(b))
		s += step
	if line.kind == InterestLine.Kind.LADDER:
		# Rungs across the local X, every 0.35 m -- reads as a ladder at a
		# glance -- and the front arrow: local -Z is the side a body climbs
		# from (InterestLine.front()).
		var r: float = 0.0
		while r <= length + 0.01:
			var at: Vector3 = line.curve.sample_baked(minf(r, length))
			lines.append(at + Vector3(-0.25, 0.0, 0.0))
			lines.append(at + Vector3(0.25, 0.0, 0.0))
			r += 0.35
		var mid: Vector3 = line.curve.sample_baked(length * 0.5)
		lines.append(mid)
		lines.append(mid + Vector3(0.0, 0.0, -0.7))
		for wing in [Vector3(0.12, 0.0, -0.5), Vector3(-0.12, 0.0, -0.5),
				Vector3(0.0, 0.12, -0.5), Vector3(0.0, -0.12, -0.5)]:
			lines.append(mid + Vector3(0.0, 0.0, -0.7))
			lines.append(mid + wing)
	gizmo.add_lines(lines, material)
	gizmo.add_collision_segments(lines)
