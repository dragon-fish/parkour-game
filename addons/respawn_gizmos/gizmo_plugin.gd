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
	create_material("mirror", Color(0.45, 0.78, 1.0))
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
			["spawn", Color(0.75, 0.4, 1.0, 0.25)],
			["mirror", Color(0.45, 0.78, 1.0, 0.18)]]:
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
	return node is Checkpoint or node is SpawnPoint or node is InterestLine or node is Mirror

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node: Node3D = gizmo.get_node_3d()
	if node is InterestLine:
		_redraw_interest_line(gizmo, node)
		return
	if node is Mirror:
		_redraw_mirror(gizmo, node)
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

func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	if gizmo.get_node_3d() is Mirror:
		return ["right edge", "left edge", "top edge", "bottom edge"][id]
	return "yaw"

func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	var node: Node3D = gizmo.get_node_3d()
	# BOTH the size and the origin. Dragging ONE edge moves the other three
	# nowhere, which for a rectangle centred on its origin means the origin
	# itself has to shift -- so a cancelled drag has two things to put back,
	# and a named pair is what keeps the two commits below honest.
	if node is Mirror:
		return {"size": (node as Mirror).size, "position": node.global_position}
	return node.global_rotation

func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool,
		camera: Camera3D, screen_pos: Vector2) -> void:
	var node: Node3D = gizmo.get_node_3d()
	if node is Mirror:
		_set_mirror_size_handle(node as Mirror, id, camera, screen_pos)
		return
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
	if node is Mirror:
		var was: Dictionary = restore
		if cancel:
			(node as Mirror).size = was["size"]
			node.global_position = was["position"]
			return
		var mirror_ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		mirror_ur.create_action("Resize mirror")
		mirror_ur.add_do_property(node, "size", (node as Mirror).size)
		mirror_ur.add_do_property(node, "global_position", node.global_position)
		mirror_ur.add_undo_property(node, "size", was["size"])
		mirror_ur.add_undo_property(node, "global_position", was["position"])
		mirror_ur.commit_action()
		return
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


# --- mirrors ---------------------------------------------------------------

## Handle ids: one per EDGE, not one per axis.
##
## ✅ THE OWNER: "有时候想对齐一个平面还是单独拉四个边比较方便." Godot's own
## centred primitives (BoxMesh, BoxShape3D, CSGBox3D) all resize symmetrically
## about their origin, and the first version of this followed them -- but a
## mirror is usually being fitted INTO something, a frame or a wall recess, and
## then the edge you are not dragging has to stay exactly where you put it.
## Symmetric sizing is still one field away in the inspector.
const MIRROR_RIGHT_HANDLE := 0
const MIRROR_LEFT_HANDLE := 1
const MIRROR_TOP_HANDLE := 2
const MIRROR_BOTTOM_HANDLE := 3
## The smallest a drag may make a pane. Not a design limit -- it just stops a
## handle dragged through the centre from collapsing the gizmo it lives on.
const MIN_MIRROR_SIZE := 0.1

## Mirror builds its glass in _ready(), which never runs in the editor, so the
## node is invisible and un-clickable there. ✅ THE OWNER: "镜子实体在编辑器里
## 完全看不见摸不着，可能会让我很难摆，希望可以显示一个面片，可以通过手柄调整宽高."
##
## A gizmo rather than a @tool preview mesh, for the reason this file's header
## already gives about the respawn capsule: a runtime-built mesh has no owner,
## so the editor's selection ray refuses to see it. Gizmo lines DO take
## collision segments, so the rectangle is clickable.
##
## THE ARROW IS NOT DECORATION. A mirror faces its own -Z (the Checkpoint
## convention) and a pane placed backwards reflects the wall behind it, which
## looks like a broken mirror rather than a turned one.
func _redraw_mirror(gizmo: EditorNode3DGizmo, mirror: Mirror) -> void:
	var half_x: float = maxf(mirror.size.x, MIN_MIRROR_SIZE) * 0.5
	var half_y: float = maxf(mirror.size.y, MIN_MIRROR_SIZE) * 0.5
	var corners := [
		Vector3(-half_x, -half_y, 0.0), Vector3(half_x, -half_y, 0.0),
		Vector3(half_x, half_y, 0.0), Vector3(-half_x, half_y, 0.0),
	]
	var lines := PackedVector3Array()
	for i in 4:
		lines.append(corners[i])
		lines.append(corners[(i + 1) % 4])
	# One diagonal pair, so a pane seen edge-on still reads as a surface rather
	# than as a single line.
	lines.append(corners[0])
	lines.append(corners[2])
	lines.append(corners[1])
	lines.append(corners[3])
	# The facing stub, along -Z.
	var reach: float = minf(half_x, half_y) * 0.6
	lines.append(Vector3.ZERO)
	lines.append(Vector3(0.0, 0.0, -reach))
	for tip in [Vector3(reach * 0.25, 0.0, -reach * 0.7), Vector3(-reach * 0.25, 0.0, -reach * 0.7)]:
		lines.append(Vector3(0.0, 0.0, -reach))
		lines.append(tip)

	var material: StandardMaterial3D = get_material("mirror", gizmo)
	gizmo.add_lines(lines, material)
	gizmo.add_collision_segments(lines)

	# ⚠️ THE FILL FACES THE REFLECTIVE SIDE, WHICH IS -Z. PlaneMesh.FACE_Z faces
	# +Z and the fill material culls backfaces, so left alone this drew the pane
	# on the mirror's BACK: nothing visible from the side that reflects, and a
	# translucent sheet visible from the side that does not. ✅ THE OWNER: "你的
	# 半透明写反了吧，应该是反射面填充半透明比较符合直觉?"
	#
	# Deliberately NOT made double-sided. One-sided, the fill is a second signal
	# agreeing with the arrow: if you can see the glass, you are in front of it.
	var fill := PlaneMesh.new()
	fill.size = Vector2(half_x * 2.0, half_y * 2.0)
	fill.orientation = PlaneMesh.FACE_Z
	gizmo.add_mesh(fill, _fills["mirror"], Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))

	# Order matters: the index in this array IS the handle id.
	gizmo.add_handles(PackedVector3Array([
		Vector3(half_x, 0.0, 0.0),    # MIRROR_RIGHT_HANDLE
		Vector3(-half_x, 0.0, 0.0),   # MIRROR_LEFT_HANDLE
		Vector3(0.0, half_y, 0.0),    # MIRROR_TOP_HANDLE
		Vector3(0.0, -half_y, 0.0),   # MIRROR_BOTTOM_HANDLE
	]), get_material("handles", gizmo), PackedInt32Array())

## Drags one edge of the pane. The drag lives in the mirror's OWN plane -- the
## mouse ray is crossed with it and the hit read back in local space, so the
## handle tracks the cursor at any viewing angle instead of only head-on.
func _set_mirror_size_handle(mirror: Mirror, id: int, camera: Camera3D, screen_pos: Vector2) -> void:
	var plane := Plane(mirror.global_transform.basis.z.normalized(), mirror.global_position)
	var hit: Variant = plane.intersects_ray(
		camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	var local: Vector3 = mirror.global_transform.affine_inverse() * (hit as Vector3)
	var half: Vector2 = mirror.size * 0.5
	var size: Vector2 = mirror.size
	# Where the origin has to move so the three edges NOT being dragged stay
	# exactly where they are. Local, and converted through the basis below so a
	# rotated or scaled mirror behaves the same as an axis-aligned one.
	var shift := Vector3.ZERO
	match id:
		MIRROR_RIGHT_HANDLE:
			var edge: float = maxf(local.x, -half.x + MIN_MIRROR_SIZE)
			size.x = edge + half.x
			shift.x = (edge - half.x) * 0.5
		MIRROR_LEFT_HANDLE:
			var edge: float = minf(local.x, half.x - MIN_MIRROR_SIZE)
			size.x = half.x - edge
			shift.x = (edge + half.x) * 0.5
		MIRROR_TOP_HANDLE:
			var edge: float = maxf(local.y, -half.y + MIN_MIRROR_SIZE)
			size.y = edge + half.y
			shift.y = (edge - half.y) * 0.5
		MIRROR_BOTTOM_HANDLE:
			var edge: float = minf(local.y, half.y - MIN_MIRROR_SIZE)
			size.y = half.y - edge
			shift.y = (edge + half.y) * 0.5
	mirror.size = size
	mirror.global_position += mirror.global_transform.basis * shift
