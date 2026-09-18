extends ParkourTest

# The original's WallNormal points out of the wall on every interaction volume,
# but InterestLine.front() means opposite things on a ladder and a ledge walk.
# Extracted ledge walks came out turned round because the shell builder handed
# WallNormal to both as-is.

const ShellBuilder := preload("res://tools/me_level/shell_builder.gd")

func _front(kind: String, wall: Array) -> Vector3:
	return -ShellBuilder._front_basis({"kind": kind, "wall": wall}).z

func test_a_ledge_walk_faces_the_wall_its_normal_points_out_of() -> void:
	assert_almost_eq(_front("ledgewalk", [1.0, 0.0, 0.0]).x, -1.0, 0.001,
		"a ledge walk's front must point at the wall, against WallNormal")

func test_a_ladder_is_climbed_from_the_side_its_normal_points_to() -> void:
	assert_almost_eq(_front("ladder", [1.0, 0.0, 0.0]).x, 1.0, 0.001,
		"a ladder's front is the side it is climbed from, along WallNormal")
