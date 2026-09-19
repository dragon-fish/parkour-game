class_name TriggerDebug
extends Node

## F3: the level's triggers, air walls and interest lines, drawn as lines in
## one colour per kind, each named at its centre. Nothing of these shows
## otherwise -- a trigger has no picture, and an air wall is exactly the thing
## you cannot see.
##
## Built when switched on, from whatever is loaded then, and hung under the
## nodes it draws so a moving one (a lift car's zones) takes its lines along.
## Level geometry is left out: a chapter has thousands of those bodies, and
## they are drawn already.

const KEY := KEY_F3

const AIR_WALL := Color(1.0, 0.2, 0.2)
const AIR_WALL_NO_INTERACTION := Color(1.0, 0.55, 0.1)
const SLIDE := Color(0.2, 0.95, 0.95)
const SOFT_LANDING := Color(0.3, 1.0, 0.3)
const DEATH := Color(0.6, 0.2, 0.9)
const HAZARD := Color(1.0, 0.2, 0.8)
const MODIFIER := Color(0.2, 0.7, 0.6)
const CHECKPOINT := Color(0.3, 0.5, 1.0)
const USE_ZONE := Color(1.0, 0.95, 0.2)
const MATINEE_TRIGGER := Color(0.95, 0.95, 0.95)
const LEVEL_END := Color(1.0, 0.8, 0.2)
const GLASS := Color(0.6, 0.85, 1.0)

## Opacity of a shape's faces behind its lines.
const FILL_ALPHA := 0.2

const LABEL_SIZE := 48
## How far the direction and facing arrows reach, metres.
const ARROW := 0.7

var _shown := false
## Everything built for the current showing, freed when it goes off.
var _drawn: Array[Node] = []
var _materials: Dictionary = {}
var _fills: Dictionary = {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY:
		set_shown(not _shown)


func set_shown(on: bool) -> void:
	_shown = on
	_clear()
	if on:
		_build()


func overlay_shown() -> bool:
	return _shown


func _clear() -> void:
	for node in _drawn:
		if is_instance_valid(node):
			node.queue_free()
	_drawn.clear()


func _build() -> void:
	for node in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var kind: Array = _kind_of(node)
		if not kind.is_empty():
			_draw_shapes(node as CollisionObject3D, kind[0], kind[1])
	for line in get_tree().get_nodes_in_group("interest_lines"):
		if line is InterestLine:
			_draw_line(line)


## [colour, type name] a body or area is drawn with, or empty to leave it out.
func _kind_of(node: Node) -> Array:
	var parent := node.get_parent()
	if parent is InterestLine:
		return []
	if parent is BreakableGlass:
		return [GLASS, "玻璃"]
	if node is LevelEnd:
		return [LEVEL_END, "通关"]
	if node is DeathVolume:
		return [DEATH, "死亡区"]
	if node is Checkpoint or parent is Checkpoint:
		return [CHECKPOINT, "检查点"]
	if node is UseZone:
		return [USE_ZONE, "按钮"]
	if node is ModifierVolume:
		for spec in (node as ModifierVolume).apply:
			if spec != null and spec.effect == Status.Effect.STAGGER:
				return [HAZARD, "伤害区"]
		return [MODIFIER, "状态体积"]
	if node is Area3D and parent is Matinee:
		return [MATINEE_TRIGGER, "动画触发"]
	if node.is_in_group(Probes.UNCONTROLLED_SLIDE_GROUP):
		return [SLIDE, "滑坡"]
	if node.is_in_group(Probes.SOFT_LANDING_GROUP):
		return [SOFT_LANDING, "软着陆"]
	if parent != null and parent.name == "AirWalls":
		if node.is_in_group(Probes.NO_INTERACTION_GROUP):
			return [AIR_WALL_NO_INTERACTION, "无交互空气墙"]
		return [AIR_WALL, "空气墙"]
	return []


## Type names of the interest-line kinds, for the labels.
const LINE_TYPES := {
	InterestLine.Kind.ZIPLINE: "滑索",
	InterestLine.Kind.SWING: "秋千",
	InterestLine.Kind.BALANCE: "平衡木",
	InterestLine.Kind.LADDER: "梯子",
	InterestLine.Kind.LEDGE_WALK: "壁架",
}


func _material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colour
		_materials[colour] = m
	return _materials[colour]


## The same colour, faint, for a shape's faces.
func _fill(colour: Color) -> StandardMaterial3D:
	if not _fills.has(colour):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(colour, FILL_ALPHA)
		_fills[colour] = m
	return _fills[colour]


func _draw_shapes(body: CollisionObject3D, colour: Color, type: String) -> void:
	var bounds := AABB()
	var first := true
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var mesh := shape_node.shape.get_debug_mesh()
		var drawn := MeshInstance3D.new()
		drawn.mesh = mesh
		# The debug mesh is edges AND faces: one material for both drew every
		# volume as a solid box.
		for surface in mesh.get_surface_count():
			var lines := mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_LINES
			drawn.set_surface_override_material(surface, _material(colour) if lines else _fill(colour))
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shape_node.add_child(drawn, false, Node.INTERNAL_MODE_BACK)
		_drawn.append(drawn)
		var box: AABB = shape_node.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		_label(body, "%s:%s" % [type, body.name], bounds.get_center(), colour)


## The editor gizmo's line, direction and facing: the axis in the kind's
## colour, beads on its ends, an arrowhead down the line at its middle and an
## arrow out of its -Z (InterestLine.front()).
func _draw_line(line: InterestLine) -> void:
	if line.curve == null or line.curve.point_count < 2:
		return
	var colour: Color = InterestLine.KIND_COLORS.get(line.kind, Color.WHITE)
	var points := line.curve.get_baked_points()
	var lines := PackedVector3Array()
	for i in range(points.size() - 1):
		lines.append(points[i])
		lines.append(points[i + 1])
	var length := line.curve.get_baked_length()
	var mid := line.curve.sample_baked(length * 0.5)
	var ahead := line.curve.sample_baked(minf(length * 0.5 + 0.05, length))
	var along := (ahead - mid).normalized() if (ahead - mid).length() > 0.0001 else Vector3.UP
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	var tip := mid + along * 0.25
	for wing in [side, -side]:
		lines.append(tip)
		lines.append(tip - along * 0.15 + wing * 0.1)
	var front := line.global_transform.basis.inverse() * line.front()
	var out := mid + front * ARROW
	lines.append(mid)
	lines.append(out)
	var across := front.cross(Vector3.UP).normalized()
	for wing in [across, -across]:
		lines.append(out)
		lines.append(out - front * 0.2 + wing * 0.12)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(colour))
	for p in lines:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var drawn := MeshInstance3D.new()
	drawn.mesh = mesh
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.add_child(drawn, false, Node.INTERNAL_MODE_BACK)
	_drawn.append(drawn)
	var bead := SphereMesh.new()
	bead.radius = 0.07
	bead.height = 0.14
	bead.radial_segments = 10
	bead.rings = 5
	bead.material = _material(colour)
	for at in [line.curve.get_point_position(0), line.curve.get_point_position(line.curve.point_count - 1)]:
		var end := MeshInstance3D.new()
		end.mesh = bead
		end.position = at
		line.add_child(end, false, Node.INTERNAL_MODE_BACK)
		_drawn.append(end)
	_label(line, "%s:%s" % [LINE_TYPES.get(line.kind, "兴趣线"), line.name], mid + Vector3.UP * 0.3, colour)


func _label(parent: Node3D, text: String, at: Vector3, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = LABEL_SIZE
	label.pixel_size = 0.004
	label.modulate = colour
	label.outline_modulate = Color.BLACK
	label.outline_size = 8
	parent.add_child(label, false, Node.INTERNAL_MODE_BACK)
	_drawn.append(label)
