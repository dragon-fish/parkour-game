extends ParkourTest

# [ME:DERIVED 05 §5.6.5] The level marker every "interact along a line"
# move reads. A sagging cable is the shape that matters: a straight line is
# its two-point degenerate case.

const TestWorld = preload("res://tests/world_fixture.gd")

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

func test_the_line_draws_nothing_of_its_own() -> void:
	# The level's own cable or pole is what the player sees; the line is drawn
	# only by the trigger overlay (F3, TriggerDebug).
	_line = _sagging_line()
	await step(1)
	for child in _line.get_children():
		assert_false(child is MeshInstance3D, "the interest line drew a mesh of its own")

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

func test_the_player_knows_which_line_it_is_inside() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(5)
	var player: Player = world["player"]
	_line = _sagging_line()
	# Lower the cable so a standing body's capsule sits inside its volume.
	_line.position = Vector3(0.0, -2.2, 0.0)
	await step(3)
	assert_eq(player.nearest_interest_line(InterestLine.Kind.ZIPLINE), _line, \
		"the player standing inside the volume does not report the line")
	assert_null(player.nearest_interest_line(InterestLine.Kind.SWING), \
		"a zipline must not be reported as a swing")
	player.reset_state()
	assert_null(player.nearest_interest_line(InterestLine.Kind.ZIPLINE), \
		"reset_state() must forget the lines from the previous life")
	TestWorld.teardown(world)
	await step(1)

## A moving body with the two hooks Player has. CharacterBody3D so that Area3D
## detects it the same way it detects the real player.
class _Listener extends CharacterBody3D:
	var entered: Array = []
	var exited: Array = []
	func _init() -> void:
		var shape := CollisionShape3D.new()
		shape.shape = SphereShape3D.new()
		add_child(shape)
		# A gameplay volume watches Arena.PLAYER_LAYER and nothing else, so a
		# stand-in for the body has to be on it. The real one is put there by
		# player_builder; on layer 1 alone this listener is invisible to the
		# volume, exactly as a piece of the level is.
		collision_layer = 1 | Arena.PLAYER_LAYER
	func enter_interest_line(line: InterestLine) -> void:
		entered.append(line)
	func exit_interest_line(line: InterestLine) -> void:
		exited.append(line)

func test_picking_a_kind_seeds_that_kinds_reach() -> void:
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.SWING
	assert_eq(line.reach_radius, InterestLine.KIND_REACH[InterestLine.Kind.SWING],
		"choosing SWING did not seed the bar's own reach")
	# Written after the kind, the way a scene file lists them, the author's
	# own number wins.
	line.reach_radius = 0.3
	assert_eq(line.reach_radius, 0.3, "an explicit reach was not kept")
	line.free()
