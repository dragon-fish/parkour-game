extends ParkourTest

# The block tool's geometry, which is the part of it a headless test can reach.
# How the drag FEELS is not in here and cannot be.

const Geometry := preload("res://addons/GodotchUp/block_geometry.gd")

func _is_right_handed(basis: Basis) -> bool:
	return basis.determinant() > 0.0

func test_a_floor_gives_the_world_grid_back() -> void:
	var basis: Basis = Geometry.face_basis(Vector3.UP)
	assert_almost_eq(basis.y, Vector3.UP, Vector3.ONE * 0.001, "up column is not the normal")
	assert_almost_eq(basis.x, Vector3.RIGHT, Vector3.ONE * 0.001, \
		"a floor drew its rectangle on some tangent other than the world grid")

func test_a_wall_basis_stays_right_handed() -> void:
	# A left-handed basis mirrors every block built on a wall, and nothing
	# symmetrical can show it.
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, \
			Vector3(1, 1, 0).normalized()]:
		var basis: Basis = Geometry.face_basis(normal)
		assert_almost_eq(basis.y, normal, Vector3.ONE * 0.001, \
			"up column is not the normal for %s" % normal)
		assert_true(_is_right_handed(basis), "basis for %s is mirrored" % normal)
		assert_almost_eq(basis.x.dot(basis.y), 0.0, 0.001, "basis for %s is not square" % normal)

func test_a_drag_becomes_a_box_that_sits_on_the_anchor() -> void:
	var plan: Dictionary = Geometry.block_from_drag(
		Vector3.ZERO, Basis.IDENTITY, Vector2(3.0, 2.0), 0.5, 0.5)
	assert_almost_eq(plan["size"] as Vector3, Vector3(3.0, 0.5, 2.0), Vector3.ONE * 0.001)
	# The box rests ON the surface, so its centre is half a thickness above it.
	assert_almost_eq((plan["transform"] as Transform3D).origin, \
		Vector3(1.5, 0.25, 1.0), Vector3.ONE * 0.001, "the block is not sitting on its anchor")

func test_dragging_backwards_still_makes_a_positive_box() -> void:
	var plan: Dictionary = Geometry.block_from_drag(
		Vector3.ZERO, Basis.IDENTITY, Vector2(-3.0, -2.0), 0.5, 0.5)
	assert_almost_eq(plan["size"] as Vector3, Vector3(3.0, 0.5, 2.0), Vector3.ONE * 0.001, \
		"a backwards drag produced a negative size")
	assert_almost_eq((plan["transform"] as Transform3D).origin, \
		Vector3(-1.5, 0.25, -1.0), Vector3.ONE * 0.001, "the block grew the wrong way")

func test_a_click_lays_one_tile_rather_than_nothing() -> void:
	# A zero-width CSG box is degenerate: it draws nothing and its size handles
	# land on top of each other, so there is no way to pull it back open.
	var plan: Dictionary = Geometry.block_from_drag(
		Vector3.ZERO, Basis.IDENTITY, Vector2.ZERO, 0.5, 0.5)
	assert_almost_eq(plan["size"] as Vector3, Vector3(0.5, 0.5, 0.5), Vector3.ONE * 0.001, \
		"a click with no drag produced a block with no volume")

func test_snapping_off_is_a_setting_not_a_crash() -> void:
	assert_eq(Geometry.snap(1.234, 0.0), 1.234, "a zero step should leave the value alone")
	assert_eq(Geometry.snap(1.24, 0.5), 1.0)
	assert_eq(Geometry.snap(1.26, 0.5), 1.5)

func test_a_thin_block_survives_a_coarse_grid() -> void:
	# Thickness is the caller's to choose and the grid may not raise it. While
	# the two shared a floor, asking for a 0.1 block on a 1 m grid returned a
	# 1 m slab.
	var plan: Dictionary = Geometry.block_from_drag(
		Vector3.ZERO, Basis.IDENTITY, Vector2(2.0, 2.0), 0.1, 1.0)
	assert_almost_eq((plan["size"] as Vector3).y, 0.1, 0.001, \
		"the snap grid inflated the block's thickness")
	assert_almost_eq((plan["transform"] as Transform3D).origin.y, 0.05, 0.001, \
		"a thin block is not resting on its anchor")

func test_a_cylinder_stands_on_its_footprint() -> void:
	var plan: Dictionary = Geometry.cylinder_from_drag(
		Vector3.ZERO, Basis.IDENTITY, 2.0, 0.2, 0.2)
	assert_almost_eq(plan["radius"] as float, 2.0, 0.001)
	assert_almost_eq(plan["height"] as float, 0.2, 0.001)
	# A CSGCylinder3D is centred on its own origin, so resting on the surface
	# means half a height up -- not level with it.
	assert_almost_eq((plan["transform"] as Transform3D).origin, \
		Vector3(0.0, 0.1, 0.0), Vector3.ONE * 0.001, "the cylinder is sunk into its surface")

func test_a_sphere_is_centred_where_the_drag_started() -> void:
	# Dragging a centre and a radius means the centre is where you pointed.
	# This used to lift the ball to rest on the surface, which put it somewhere
	# nobody asked for.
	var plan: Dictionary = Geometry.sphere_from_drag(
		Vector3(2.0, 1.0, -3.0), Basis.IDENTITY, 1.5, 0.2)
	assert_almost_eq(plan["radius"] as float, 1.5, 0.001)
	assert_almost_eq((plan["transform"] as Transform3D).origin, \
		Vector3(2.0, 1.0, -3.0), Vector3.ONE * 0.001, "the ball drifted off its centre")

func test_a_cylinder_on_a_wall_grows_out_of_the_wall() -> void:
	# The regression this guards: using the world's up instead of the face's
	# puts everything drawn on a wall inside the wall.
	var wall: Basis = Geometry.face_basis(Vector3.RIGHT)
	var plan: Dictionary = Geometry.cylinder_from_drag(Vector3.ZERO, wall, 1.0, 0.4, 0.2)
	assert_almost_eq((plan["transform"] as Transform3D).origin, \
		Vector3(0.2, 0.0, 0.0), Vector3.ONE * 0.001, "the cylinder grew along the wrong axis")

func test_a_click_with_no_drag_still_gives_a_round_solid_a_radius() -> void:
	var plan: Dictionary = Geometry.cylinder_from_drag(
		Vector3.ZERO, Basis.IDENTITY, 0.0, 0.2, 0.2)
	assert_almost_eq(plan["radius"] as float, 0.2, 0.001, \
		"a click produced a cylinder with no radius")

func test_a_solid_lands_where_it_was_drawn_under_a_moved_parent() -> void:
	# The hazard: a Node3D's transform is read against its parent, so handing
	# it the world placement puts a solid drawn on a rotated platform somewhere
	# off to the side. One inverse of the parent's GLOBAL transform is the
	# whole correction -- that transform already carries the ancestor chain.
	var parent := Transform3D(Basis(Vector3.UP, deg_to_rad(37.0)), Vector3(10.0, -4.0, 6.0))
	var world := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20.0)), Vector3(-2.0, 1.5, 3.0))
	var local: Transform3D = Geometry.local_placement(parent, world)
	assert_almost_eq((parent * local).origin, world.origin, Vector3.ONE * 0.0001, \
		"the solid drifted off the point it was drawn at")
	assert_true((parent * local).is_equal_approx(world), "the solid came out skewed")
