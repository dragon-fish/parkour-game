extends ParkourTest

# BarbedWire generates geometry and nothing else -- no volume, no collision --
# so what is worth pinning is that the generator answers the curve it was
# given, and that it refuses rather than producing nonsense when it cannot.
#
# The coil's look is a tuning value and gets no assertion: nothing here checks
# that 3 turns a metre is prettier than 5.

func _wire(from: Vector3, to: Vector3) -> BarbedWire:
	var wire := BarbedWire.new()
	var line := Curve3D.new()
	line.add_point(from)
	line.add_point(to)
	wire.curve = line
	add_child_autofree(wire)
	return wire

func _mesh_of(wire: BarbedWire) -> ArrayMesh:
	for child in wire.get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh as ArrayMesh
	return null

func test_a_two_point_curve_grows_a_coil() -> void:
	var wire := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	await step(1)
	var mesh := _mesh_of(wire)
	assert_not_null(mesh, "no mesh was built for a perfectly ordinary curve")
	assert_gt(mesh.get_surface_count(), 0, "the mesh has no surfaces")
	assert_gt(mesh.surface_get_array_len(0), 0, "the surface has no vertices")

func test_the_coil_wraps_the_path_rather_than_following_it() -> void:
	# The curve is the AXIS. A coil of radius r stands off it by r on every
	# side, so the geometry is at least 2r across even though the path itself
	# is a line with no width. Bracketed rather than pinned, because the
	# silhouette is the loop plus the strand wrapped round it plus whatever
	# barbs happen to land on the outside of a turn.
	var wire := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	wire.coil_radius = 0.3
	await step(1)
	var box: AABB = _mesh_of(wire).get_aabb()
	var floor_span: float = 2.0 * wire.coil_radius
	var ceiling: float = 2.0 * (wire.coil_radius + wire.wire_radius + wire.barb_length)
	assert_between(box.size.x, floor_span, ceiling, \
		"the coil is not standing off the axis")
	assert_between(box.size.y, floor_span, ceiling, \
		"the coil is flat instead of wound")
	assert_gt(box.size.z, 3.5, "the coil does not run the length of the path")

func test_a_wider_coil_makes_wider_geometry() -> void:
	var narrow := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	narrow.coil_radius = 0.2
	var wide := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	wide.coil_radius = 0.5
	await step(1)
	assert_gt(_mesh_of(wide).get_aabb().size.x, _mesh_of(narrow).get_aabb().size.x + 0.4, \
		"coil_radius did not reach the geometry")

func test_the_same_seed_grows_the_same_wire() -> void:
	# An author has to be able to trust that the run they placed is the run
	# that ships. A barb layout redrawn on every load would make a level look
	# different every time it was opened.
	var a := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	var b := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	a.barb_seed = 7
	b.barb_seed = 7
	await step(1)
	assert_eq(_mesh_of(a).get_aabb(), _mesh_of(b).get_aabb(), \
		"two wires with the same seed grew differently")

func test_a_different_seed_moves_the_barbs_without_changing_how_many() -> void:
	var a := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	var b := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	a.barb_seed = 1
	b.barb_seed = 2
	await step(1)
	assert_eq(_mesh_of(a).surface_get_array_len(0), _mesh_of(b).surface_get_array_len(0), \
		"a different seed changed the barb COUNT, so the dial is doing two jobs")

func test_a_curve_too_short_to_wind_builds_nothing_and_says_so() -> void:
	var wire := BarbedWire.new()
	var line := Curve3D.new()
	line.add_point(Vector3.ZERO)
	wire.curve = line
	add_child_autofree(wire)
	await step(1)
	assert_null(_mesh_of(wire), "a one-point curve produced geometry anyway")
	assert_gt(wire._get_configuration_warnings().size(), 0, \
		"a one-point curve did not warn")

func test_a_strand_thicker_than_the_coil_refuses_rather_than_closing_up() -> void:
	# Past this the tube swallows the loop and the coil renders as a solid rod
	# -- geometry that looks like a mistake and is one.
	var wire := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -4.0))
	wire.wire_radius = 0.4
	wire.coil_radius = 0.3
	await step(1)
	assert_null(_mesh_of(wire), "an impossible strand still built a mesh")
	assert_gt(wire._get_configuration_warnings().size(), 0, "it did not warn either")

func test_the_triangle_estimate_answers_the_dials_that_drive_it() -> void:
	# The number the warning quotes has to move with the dials, or it is
	# advice about someone else's wire.
	var wire := _wire(Vector3.ZERO, Vector3(0.0, 0.0, -8.0))
	await step(1)
	var before: int = wire.triangle_estimate()
	wire.samples_per_coil = wire.samples_per_coil * 2
	await step(1)
	assert_gt(wire.triangle_estimate(), before, \
		"samples_per_coil is named as the cheapest dial to drop but does not move the estimate")
