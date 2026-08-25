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

## Pumps forward until the jump window opens, or fails the assertion.
func _pump_until_window(player: Player, move: SwingMove) -> void:
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
		if move.jump_window_open():
			return
	assert_true(false, "300 ticks of pumping never opened the jump window")

func test_the_exit_jump_launches_at_the_fixed_angle() -> void:
	# ✅ THE OWNER's ME measurement: the launch angle is the SAME every time --
	# MVP rules it at 45 degrees forward-up, at exit_speed, under the exit
	# gravity window.
	var player: Player = await _swinging_player()
	await step(12)
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	await _pump_until_window(player, move)
	var forward: Vector3 = move.swing_forward()
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "the jump never left the bar")
	var v: Vector3 = player.velocity
	var cfg_swing: SwingConfig = player.config.swing
	assert_almost_eq(v.length(), cfg_swing.exit_speed, 0.35,
		"the launch speed is %.2f, configured %.2f" % [v.length(), cfg_swing.exit_speed])
	var horizontal := Vector3(v.x, 0.0, v.z)
	var angle: float = rad_to_deg(atan2(v.y, horizontal.length()))
	assert_almost_eq(angle, cfg_swing.exit_angle_deg, 3.0,
		"the launch angle is %.1f degrees" % angle)
	assert_gt(horizontal.normalized().dot(forward), 0.95, "the launch is not forward")
	assert_almost_eq(player.effective_gravity(),
		player.config.pawn.gravity * cfg_swing.exit_gravity_multiplier, 0.001,
		"the exit gravity window is not active")

func test_a_backswing_jump_is_ignored() -> void:
	var player: Player = await _swinging_player()
	await step(12)
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	# Wait for a tick where the swing is going BACKWARD, then jump.
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
		if move.swing_omega() < -0.2:
			break
	assert_lt(move.swing_omega(), 0.0, "test setup: never caught a backswing tick")
	input.state.move = Vector2.ZERO
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.SWING,
		"a backswing jump left the bar; ME ignores it")

func test_crouch_drops_with_the_tangential_speed() -> void:
	var player: Player = await _swinging_player()
	await step(12)
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	await _pump_until_window(player, move)
	var expected: float = absf(move.tangential_speed())
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "crouch did not let go")
	assert_almost_eq(player.horizontal_speed(), expected * absf(cos(move.swing_theta())), 0.6,
		"the drop lost the swing's momentum")

func test_letting_go_starts_the_bar_cooldown_for_that_bar_only() -> void:
	var player: Player = await _swinging_player()
	await step(12)
	var other := _bar(5.0)
	var second: InterestLine = other
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(1)
	assert_false(player.line_ready(_line), "the bar just left has no cooldown")
	assert_true(player.line_ready(second), "a DIFFERENT bar was locked out too")
	second.queue_free()

func test_pumping_with_the_motion_grows_the_swing() -> void:
	# Spec §6: W 顺摆泵入后幅度增大 -- the with-motion branch, distinct from the
	# from-rest kick. Caught with too little energy for the jump window, a held
	# W must grow the swing until the window opens (against the damping).
	var player: Player = await _standing_player()
	_line = _bar(2.7)
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	player.velocity.x = 0.0
	player.velocity.z = 0.5
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.SWING:
			break
	assert_eq(player.move_manager.current_name, Move.SWING, "test setup: never caught the bar")
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	await step(12)
	assert_false(move.jump_window_open(), "test setup: the window opened without any pumping")
	input.state.move = Vector2(0.0, 1.0)
	var opened := false
	for i in 400:
		await step(1)
		if move.jump_window_open():
			opened = true
			break
	assert_true(opened, "held W never grew the swing into the jump window")

func test_the_model_leans_with_the_swing_and_stands_back_up() -> void:
	# ✅ THE OWNER, on how ME reads amplitude: "主要是靠镜头里可以看到自己身体来
	# 判断" -- the model tilts along the chain; the camera is deliberately NOT
	# pitched with it.
	var player: Player = await _swinging_player()
	await step(12)
	var move: SwingMove = player.move_manager.move_for(Move.SWING)
	var body_root := player.get_node("BodyRoot") as Node3D
	var sampled := false
	for i in 200:
		await step(1)
		if absf(move.swing_theta()) > 0.1:
			sampled = true
			break
	assert_true(sampled, "test setup: the pendulum never reached 0.1 rad")
	var expected: float = -move.swing_theta() * player.config.swing.model_pitch_follow
	assert_almost_eq(body_root.rotation.x, expected, 0.12,
		"the model lean %.2f does not track the chain %.2f" % [body_root.rotation.x, expected])
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(30)
	assert_almost_eq(body_root.rotation.x, 0.0, 0.05,
		"the lean never stood back up after letting go")
