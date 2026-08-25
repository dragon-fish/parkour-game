extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

func _vertical_ladder(at: Vector3, yaw_deg: float = 0.0) -> InterestLine:
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.LADDER
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(Vector3(0.0, 3.0, 0.0))
	line.position = at
	line.rotation.y = deg_to_rad(yaw_deg)
	add_child_autofree(line)
	return line

func test_front_is_the_nodes_minus_z_flattened() -> void:
	var line := _vertical_ladder(Vector3.ZERO, 90.0)
	await step(1)
	# yaw +90: -Z rotates onto -X.
	assert_almost_eq(line.front().x, -1.0, 0.01, "front did not follow the node yaw")
	assert_almost_eq(line.front().y, 0.0, 0.001, "front must be horizontal")
	assert_true(line.is_in_group("interest_lines"), "lines must be discoverable for the snap scan")
