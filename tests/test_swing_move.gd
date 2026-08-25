extends ParkourTest

# 05 §5.5b: a 1.2 m pendulum you pump with W/S and leave at any phase. Entry
# is MAGNETIC (the owner's ME measurement: "快要碰到横杆的时候，会帮你吸附上
# 去"); the exit jump is a lenient fixed-angle launch (Task 4).

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _line: InterestLine = null

func after_each() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

## A horizontal bar along X at `height`, marked as a SWING interest line.
func _bar(height: float) -> InterestLine:
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.SWING
	var curve := Curve3D.new()
	curve.add_point(Vector3(-2.0, height, 0.0))
	curve.add_point(Vector3(2.0, height, 0.0))
	line.curve = curve
	get_tree().root.add_child(line)
	return line

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## Jumps under a bar at 2.7 (out of the volume standing, inside at the apex --
## same arithmetic as the zipline suite's 2.7 cable).
func _swinging_player() -> Player:
	var player: Player = await _standing_player()
	_line = _bar(2.7)
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	# Real approach velocity, INJECTED rather than run up -- same technique
	# ZiplineMove's own suite uses (test_jumping_with_the_travel_direction_
	# still_catches): a run-up drifts the body sideways out of the bar's
	# 0.6 m reach_radius before the jump ever gets it into the volume. This
	# also keeps entry off the theta=0/omega=0 dead point the pump-from-rest
	# fix addresses -- a straight-up jump with no drift used to be a
	# mathematical fixed point.
	player.velocity.x = 0.0
	player.velocity.z = 1.5
	for i in 39:
		await step(1)
		if player.move_manager.current_name == Move.SWING:
			break
	assert_eq(player.move_manager.current_name, Move.SWING, "test setup: never caught the bar")
	return player

func test_walking_under_the_bar_does_not_catch_it() -> void:
	var player: Player = await _standing_player()
	_line = _bar(1.3)
	await step(10)
	assert_ne(player.move_manager.current_name, Move.SWING, "a bar may only be caught from the air")

func test_jumping_into_the_volume_catches_it() -> void:
	var player: Player = await _swinging_player()
	assert_false(player.grounded, "hanging from a bar is not standing")

func test_the_body_hangs_a_pendulum_below_the_pivot() -> void:
	var player: Player = await _swinging_player()
	await step(12)  # past the magnet fade
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	var pivot_y := 2.7
	var expected_y: float = pivot_y - player.config.swing.pendulum_length * cos(move.swing_theta())
	assert_almost_eq(player.global_position.y, expected_y, 0.03,
		"the body is not on the pendulum chain")

func test_a_free_swing_does_not_gain_energy() -> void:
	# No pump input: track the tangential speed's PEAK over two periods; the
	# later peaks must not exceed the first (integration must not self-excite).
	var player: Player = await _swinging_player()
	await step(12)
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	var first_peak := 0.0
	var later_peak := 0.0
	for i in 220:  # ~two periods at T=1.72 s
		await step(1)
		var s: float = absf(move.tangential_speed())
		if i < 110:
			first_peak = maxf(first_peak, s)
		else:
			later_peak = maxf(later_peak, s)
	assert_gt(first_peak, 0.5, "test setup: the pendulum never swung at all")
	assert_lt(later_peak, first_peak + 0.05,
		"the free pendulum grew from %.2f to %.2f" % [first_peak, later_peak])

func test_a_zipline_gate_does_not_take_a_swing_bar() -> void:
	# kind filtering both ways: the swing bar must never enter Zipline.
	var player: Player = await _swinging_player()
	assert_ne(player.move_manager.current_name, Move.ZIPLINE,
		"a SWING line was caught by the zipline gate")

func test_pumping_starts_a_swing_from_dead_rest() -> void:
	# The zero state is reachable (straight-up jump, no input) and used to be
	# a mathematical fixed point: sin(0) torque is zero and the pump guard
	# refused to perturb exact stillness. Pumping from rest must work.
	var player: Player = await _standing_player()
	_line = _bar(2.7)
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.SWING:
			break
	assert_eq(player.move_manager.current_name, Move.SWING, "test setup: never caught the bar")
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	await step(12)
	input.state.move = Vector2(0.0, 1.0)
	for i in 60:
		await step(1)
	assert_gt(absf(move.tangential_speed()), 0.3,
		"a minute of held W never moved the dead pendulum")
