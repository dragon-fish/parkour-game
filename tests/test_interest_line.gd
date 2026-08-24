extends ParkourTest

# The level marker every "interact along a line" move reads (05 §5.6.5). A
# sagging cable is the shape that matters: a straight line is its two-point
# degenerate case.

var _line: InterestLine = null

func after_each() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null

## A 3-point cable that sags: ends at y 4, middle at y 3, 8 m long in x.
func _sagging_line() -> InterestLine:
	var line := InterestLine.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(-4.0, 4.0, 0.0))
	curve.add_point(Vector3(0.0, 3.0, 0.0))
	curve.add_point(Vector3(4.0, 4.0, 0.0))
	line.curve = curve
	get_tree().root.add_child(line)
	return line

func test_offset_and_sample_round_trip() -> void:
	_line = _sagging_line()
	await step(1)
	var total: float = _line.length()
	assert_gt(total, 8.0, "a sagging 8 m span must be longer than 8 m")
	for fraction in [0.1, 0.5, 0.9]:
		var s: float = total * fraction
		var at: Vector3 = _line.sample(s)["position"]
		var back: float = _line.closest_offset(at)
		assert_almost_eq(back, s, 0.05, "round trip at %.0f%% drifted" % (fraction * 100.0))

func test_tangent_points_toward_increasing_offset() -> void:
	_line = _sagging_line()
	await step(1)
	var t: Vector3 = _line.sample(0.5)["tangent"]
	assert_almost_eq(t.length(), 1.0, 0.001, "tangent is not unit length")
	assert_gt(t.x, 0.0, "the cable runs -x -> +x, so the tangent must point +x")
	assert_lt(t.y, 0.0, "near the start the cable sags DOWN")

func test_sample_respects_the_node_transform() -> void:
	_line = _sagging_line()
	_line.position = Vector3(10.0, 0.0, 0.0)
	await step(1)
	var mid: Vector3 = _line.sample(_line.length() * 0.5)["position"]
	assert_almost_eq(mid.x, 10.0, 0.05, "the middle of the cable should sit at the node's x")

func test_a_body_entering_the_volume_is_told() -> void:
	_line = _sagging_line()
	await step(1)
	var probe := _Listener.new()
	get_tree().root.add_child(probe)
	# Drop it onto the middle of the cable, inside reach_radius.
	probe.global_position = _line.sample(_line.length() * 0.5)["position"] + Vector3(0.0, 0.2, 0.0)
	await step(3)
	assert_eq(probe.entered, [_line], "the body under the cable was not told it entered")
	probe.global_position = Vector3(0.0, 20.0, 0.0)
	await step(3)
	assert_eq(probe.exited, [_line], "the body that left was not told it exited")
	probe.queue_free()

## A moving body with the two hooks Player has. CharacterBody3D so that Area3D
## detects it the same way it detects the real player.
class _Listener extends CharacterBody3D:
	var entered: Array = []
	var exited: Array = []
	func _init() -> void:
		var shape := CollisionShape3D.new()
		shape.shape = SphereShape3D.new()
		add_child(shape)
	func enter_interest_line(line: InterestLine) -> void:
		entered.append(line)
	func exit_interest_line(line: InterestLine) -> void:
		exited.append(line)
