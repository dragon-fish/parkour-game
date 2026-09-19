extends ParkourTest

# F3 draws the air walls, triggers and interest lines, each named, and takes
# it all away again; level geometry is left alone.

var _nodes: Array[Node] = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await step(1)

func _box_body(body: CollisionObject3D, parent: Node) -> CollisionObject3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body

func _drawn_under(node: Node) -> Array:
	var out := []
	for child in node.get_children(true):
		if child is MeshInstance3D or child is Label3D:
			out.append(child)
		out.append_array(_drawn_under(child))
	return out

func test_f3_draws_walls_triggers_and_lines_and_takes_them_away() -> void:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_nodes.append(holder)
	var walls := Node3D.new()
	walls.name = "AirWalls"
	holder.add_child(walls)
	var wall := _box_body(StaticBody3D.new(), walls)
	var death := _box_body(DeathVolume.new(), holder)
	var floor := _box_body(StaticBody3D.new(), holder)
	var line := InterestLine.new()
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(Vector3(0.0, 3.0, 0.0))
	holder.add_child(line)
	var overlay := TriggerDebug.new()
	holder.add_child(overlay)
	await step(1)
	overlay.set_shown(true)
	await step(1)
	assert_false(_drawn_under(wall).is_empty(), "the air wall was not drawn")
	assert_false(_drawn_under(death).is_empty(), "the death volume was not drawn")
	assert_false(_drawn_under(line).is_empty(), "the interest line was not drawn")
	assert_true(_drawn_under(floor).is_empty(), "plain level geometry was drawn")
	var named := _drawn_under(wall).filter(func(n): return n is Label3D and n.text == wall.name)
	assert_eq(named.size(), 1, "the air wall is not named at its centre")
	overlay.set_shown(false)
	await step(1)
	assert_true(_drawn_under(wall).is_empty(), "switching off left the air wall drawn")
	assert_true(_drawn_under(line).is_empty(), "switching off left the line drawn")
