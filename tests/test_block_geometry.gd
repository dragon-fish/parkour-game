extends ParkourTest

# The block tool's geometry, which is the part of it a headless test can reach.
# How the drag FEELS is not in here and cannot be.

const Geometry := preload("res://addons/blockout_tools/block_geometry.gd")

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
