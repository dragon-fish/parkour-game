extends ParkourTest

# The projection is the whole point of the tier: "a beam is forward/back and a
# ledge is left/right" must fall out of ONE line of code plus one angle, not
# out of two key mappings.

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

func _make_line(kind: InterestLine.Kind, from: Vector3, to: Vector3) -> InterestLine:
	var line := InterestLine.new()
	line.kind = kind
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(to - from)
	line.position = from
	add_child_autofree(line)
	return line

func test_a_beam_travels_on_w_and_ignores_a_and_d() -> void:
	var cfg := BalanceConfig.new()
	var out := LineWalkMove.project_input(
		Vector2(0.0, 1.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 1.0, 0.001, "W must drive travel along the beam")
	out = LineWalkMove.project_input(
		Vector2(1.0, 0.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 0.0, 0.001, "D must not walk you off the beam")
	assert_almost_eq(out.y, 1.0, 0.001, "D is the correction instead")

func test_a_ledge_travels_on_a_and_d_and_ignores_w() -> void:
	var cfg := LedgeWalkConfig.new()
	var out := LineWalkMove.project_input(
		Vector2(1.0, 0.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 1.0, 0.001, "D must shuffle along the ledge")
	out = LineWalkMove.project_input(
		Vector2(0.0, 1.0), 0.0, deg_to_rad(cfg.body_yaw_offset_deg))
	assert_almost_eq(out.x, 0.0, 0.001, "W must not walk you off the ledge")

func test_the_foot_gate_refuses_a_body_running_past_at_ground_level() -> void:
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(0, 3, 0), Vector3(0, 3, 4))
	var body_on_it := Vector3(0, 3, 2)
	var body_below := Vector3(0, 0, 2)
	assert_true(LineWalkMove.foot_gate_at(_line, body_on_it, 0.35))
	assert_false(LineWalkMove.foot_gate_at(_line, body_below, 0.35),
		"the reach volume alone would swallow a body running past below")

# --- structural invariant: the key you press moves you the way you face ----
#
# project_input()'s output is a function of the yaw OFFSET alone -- the
# line's own heading cancels out of the algebra -- so no assertion on
# project_input() in isolation can ever catch a sign disagreement between it
# and yaw_of()/_target_yaw (the two moves have already shipped exactly that
# bug once). This drives a REAL move on a REAL line instead and checks the
# outcome: does the body actually travel toward the side it ends up facing.

const BeamStub = preload("res://tests/line_walk_beam_stub.gd")

func test_the_ledge_walk_moves_the_body_toward_its_own_right_on_d() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	# Mid-line, well clear of either end so the boundary-exit guard added
	# alongside this test cannot interfere with the measurement.
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position - Vector3(5.0, 0.0, 0.0),
		player.global_position + Vector3(5.0, 0.0, 0.0))
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(_line),
		"test setup: the ledge's reach volume never registered the player")
	# LEDGE_WALK is already registered by Player._build_moves() (Task 3), so
	# this drives the SAME instance the real game uses, through the real
	# per-tick input/physics loop -- only the entry itself is forced, since
	# no entry site is wired to LedgeWalkMove.catch_gate() yet.
	player.move_manager.start(Move.LEDGE_WALK)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"test setup: never entered the ledge walk")
	await step(20)  # past the magnet fade
	var before: Vector3 = player.global_position
	var right: Vector3 = player.global_transform.basis.x
	_world["input"].state.move = Vector2(1.0, 0.0)  # D
	await step(30)
	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(right), 0.0,
		"D on a ledge did not move the body toward its own right")

func test_a_beam_moves_the_body_toward_its_own_forward_on_w() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	_line = _make_line(InterestLine.Kind.BALANCE,
		player.global_position - Vector3(5.0, 0.0, 0.0),
		player.global_position + Vector3(5.0, 0.0, 0.0))
	await step(5)
	assert_true(player.interest_lines.has(_line),
		"test setup: the beam's reach volume never registered the player")
	# LineWalkBeamStub isolates LineWalkMove's own projection from
	# BalanceMove's pendulum -- see the stub's own note. Registered exactly
	# the way Player._build_moves() registers every real move, so this test
	# still drives the real per-tick input/physics loop rather than
	# hand-calling physics_update().
	#
	# register() (move_manager.gd's own) is a plain dictionary write with no
	# guard, so this OVERWRITES the real BalanceMove Player already
	# registered for Move.BALANCE -- the stub shadows it for the rest of this
	# test. Harmless here (nothing asks for BALANCE by name before this
	# line), but the real move is not reachable through this player again
	# once it runs.
	var stub := BeamStub.new()
	stub.player = player
	stub.config = player.config
	stub.cfg = player.config.balance
	player.move_manager.add_child(stub)
	player.move_manager.register(Move.BALANCE, stub)
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the beam")
	await step(20)  # past the magnet fade
	var before: Vector3 = player.global_position
	var forward: Vector3 = -player.global_transform.basis.z
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(30)
	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(forward), 0.0,
		"W on a beam did not move the body toward its own forward")

# --- entry gate wiring: WalkingMove and AirborneMove both ask
# LedgeWalkMove.catch_gate() before transitioning (Task 4). ------------------

func test_walking_onto_a_ledge_line_enters_the_move() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	# The line STARTS at the settled player's own position and runs away
	# from it, so the catch lands at arc-length offset 0.0 exactly -- the
	# boundary LineWalkMove.physics_update()'s `at_end` guard exists for.
	# A body caught right on the line's own start, with no input yet, must
	# not read as having already walked past that end on its first tick
	# (the old ungated form of that check did exactly that -- see its own
	# comment). Placing the catch mid-line, as an earlier version of this
	# test did, cannot exercise that path at all: closest_offset() there
	# lands nowhere near either boundary.
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position,
		player.global_position + Vector3(10.0, 0.0, 0.0))
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LEDGE_WALK:
			break
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"walking onto a ledge line's own start did not catch it")
	# No input at all for several more ticks: the boundary-exit guard must
	# not fire on a body that never pushed past the end it was caught at.
	for i in 5:
		await step(1)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"a catch at the line's own start immediately exited back to WALKING")

func test_running_past_below_a_ledge_line_does_not_enter() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	# 0.5 m above the player's feet: inside the reach volume's capsule
	# radius (0.6 m) so the line still registers in player.interest_lines,
	# but past LedgeWalkConfig.foot_snap_height (0.35 m), so it is
	# catch_gate's foot check that must refuse this, not a missed overlap.
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position + Vector3(-5.0, 0.5, 0.0),
		player.global_position + Vector3(5.0, 0.5, 0.0))
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(_line),
		"test setup: the ledge's reach volume never registered the player")
	for i in 5:
		await step(1)
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"a ledge 0.5 m overhead caught a body it should have refused")
