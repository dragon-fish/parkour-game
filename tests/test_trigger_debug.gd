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
	var named := _drawn_under(wall).filter(func(n): return n is Label3D and n.text == "空气墙:" + wall.name)
	assert_eq(named.size(), 1, "the air wall is not named at its centre")
	overlay.set_shown(false)
	await step(1)
	assert_true(_drawn_under(wall).is_empty(), "switching off left the air wall drawn")
	assert_true(_drawn_under(line).is_empty(), "switching off left the line drawn")

## Every vertex F3 drew in lines for `line`, in the line's own frame.
func _line_vertices(line: InterestLine) -> PackedVector3Array:
	var out := PackedVector3Array()
	for node in _drawn_under(line):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		# ImmediateMesh has no surface_get_primitive_type; the bead at each end
		# is the only other mesh here and it sits within 0.07 m of the line.
		for surface in mesh_node.mesh.get_surface_count():
			out.append_array(mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return out

func _line_with_reach(holder: Node3D, reach: float) -> InterestLine:
	var line := InterestLine.new()
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(Vector3(4.0, 0.0, 0.0))
	line.reach_radius = reach
	holder.add_child(line)
	return line

func test_a_line_is_ringed_at_its_reach() -> void:
	# The radius is what a level author tunes, and without the rings the line
	# says where the bar is but not how near a body has to be.
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_nodes.append(holder)
	var line := _line_with_reach(holder, 1.0)
	var overlay := TriggerDebug.new()
	holder.add_child(overlay)
	await step(1)
	overlay.set_shown(true)
	await step(1)
	# The line runs along +X, so a ring vertex stands reach_radius off it.
	var on_the_ring := 0
	var furthest := 0.0
	for vertex in _line_vertices(line):
		var off := Vector2(vertex.y, vertex.z).length()
		furthest = maxf(furthest, off)
		if absf(off - line.reach_radius) < 0.01:
			on_the_ring += 1
	assert_gt(on_the_ring, TriggerDebug.REACH_RING_SEGMENTS,
		"only %d vertices sit at the reach radius" % on_the_ring)
	assert_almost_eq(furthest, line.reach_radius, 0.01,
		"something was drawn %.2f m off the line, past its reach" % furthest)

func test_the_rings_are_the_line_own_colour() -> void:
	# One colour per kind, already carried by the line itself: a second colour
	# for the reach would only ask to be looked up.
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_nodes.append(holder)
	var line := _line_with_reach(holder, 1.0)
	line.kind = InterestLine.Kind.SWING
	var overlay := TriggerDebug.new()
	holder.add_child(overlay)
	await step(1)
	overlay.set_shown(true)
	await step(1)
	var wanted: Color = InterestLine.KIND_COLORS[InterestLine.Kind.SWING]
	var found := false
	for node in _drawn_under(line):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
			if material != null and material.albedo_color.is_equal_approx(wanted):
				found = true
	assert_true(found, "the rings were not drawn in the swing colour")
