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

func test_the_foot_gate_refuses_feet_half_a_metre_above_the_line() -> void:
	# `body_pos` is the contract foot_gate_at() actually takes: a FEET
	# position, already converted (see catch_gate() in BalanceMove /
	# LedgeWalkMove). 0.5 m clears foot_snap_height (0.35 m) by 0.15 m, so
	# this is the real edge the gate exists to refuse, not an arbitrary drop.
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(0, 3, 0), Vector3(0, 3, 4))
	var feet_on_it := Vector3(0, 3, 2)
	var feet_half_a_metre_up := Vector3(0, 3.5, 2)
	assert_true(LineWalkMove.foot_gate_at(_line, feet_on_it, 0.35))
	assert_false(LineWalkMove.foot_gate_at(_line, feet_half_a_metre_up, 0.35),
		"the reach volume alone would swallow feet running past half a metre above the line")

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
	# LEDGE_WALK is already registered by Player._build_moves(), so this
	# drives the SAME instance the real game uses, through the real
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
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	assert_eq(ledge.shuffle_direction(), 1,
		"D on a ledge did not pick the sidestep clip for a step to the body's own right")

## Twin of the test above with the curve's two points swapped. Which branch
## LedgeWalkMove._yaw_offset() takes (+90 or -90) follows the curve's point
## order, and that is deliberately NOT supposed to change which way D
## shuffles the body (test_reversing_a_ledge_lines_curve_does_not_flip_the_facing
## pins the facing side of that same guarantee). D must read as a step to the
## body's own right -- both in real displacement AND in the clip
## shuffle_direction() hands to CharacterAnimator -- on whichever branch fired.
func test_the_ledge_walk_moves_the_body_toward_its_own_right_on_d_with_a_reversed_curve() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position + Vector3(5.0, 0.0, 0.0),
		player.global_position - Vector3(5.0, 0.0, 0.0))
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(_line),
		"test setup: the ledge's reach volume never registered the player")
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
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	assert_eq(ledge.shuffle_direction(), 1,
		"D on a ledge did not pick the sidestep clip for a step to the body's own right")

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
	# The line STARTS genuinely underfoot -- Probes.feet_y(), 0.9 m below the
	# settled player's own centre, not the centre itself -- and runs away
	# from there, so the catch lands at arc-length offset 0.0 exactly, AND
	# this is the one test that proves a flush walk-on (no fall required)
	# actually works. The boundary LineWalkMove.physics_update()'s `at_end`
	# guard is what offset 0.0 exercises: a body caught right on the line's
	# own start, with no input yet, must not read as having already walked
	# past that end on its first tick (the old ungated form of that check did
	# exactly that -- see its own comment). A catch placed mid-line cannot
	# exercise that path at all: closest_offset() there lands nowhere near
	# either boundary.
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		feet, feet + Vector3(10.0, 0.0, 0.0))
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
	# 0.5 m above the player's FEET (Probes.feet_y(), not global_position --
	# the centre already sits 0.9 m above the feet on its own): inside the
	# reach volume's capsule radius (0.6 m) so the line still registers in
	# player.interest_lines, but past LedgeWalkConfig.foot_snap_height
	# (0.35 m), so it is catch_gate's foot check that must refuse this, not a
	# missed overlap.
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		feet + Vector3(-5.0, 0.5, 0.0),
		feet + Vector3(5.0, 0.5, 0.0))
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(_line),
		"test setup: the ledge's reach volume never registered the player")
	for i in 5:
		await step(1)
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"a ledge 0.5 m overhead caught a body it should have refused")

func test_rising_through_a_ledge_line_overhead_does_not_catch_it() -> void:
	# [ME] climbing and jumping outrank the ledge walk: a body on its way UP
	# past a ledge line is not pulled onto it. Only a body settling onto the
	# line from above (or walking onto it) is caught.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		feet + Vector3(-5.0, 0.8, 0.0),
		feet + Vector3(5.0, 0.8, 0.0))
	await step(5)
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	input.release_jump()
	for i in 40:
		await step(1)
		if player.velocity.y <= 0.0:
			break
		assert_ne(player.move_manager.current_name, Move.LEDGE_WALK,
			"a ledge line was caught by a body still rising through it")

# --- yaw sign: the "-Z points at the wall" convention must be what decides,
# not the curve's own drawing direction. ------------------------------------

func test_reversing_a_ledge_lines_curve_does_not_flip_the_facing() -> void:
	# _yaw_offset()'s magnitude (LedgeWalkConfig.body_yaw_offset_deg, 90) only
	# says "turn a quarter turn off the tangent" -- which of the two
	# perpendicular directions that lands on is decided by InterestLine.front()
	# (the node's own -Z), NOT by which way the curve's two points happen to
	# be ordered. Build the identical wall-facing line twice, points reversed
	# the second time, and confirm the resulting facing is the same either way.
	var move := LedgeWalkMove.new()
	add_child_autofree(move)
	move.cfg = LedgeWalkConfig.new()

	var forward_line := InterestLine.new()
	forward_line.kind = InterestLine.Kind.LEDGE_WALK
	forward_line.curve = Curve3D.new()
	forward_line.curve.add_point(Vector3.ZERO)
	forward_line.curve.add_point(Vector3(4, 0, 0))
	add_child_autofree(forward_line)

	var reversed_line := InterestLine.new()
	reversed_line.kind = InterestLine.Kind.LEDGE_WALK
	reversed_line.curve = Curve3D.new()
	reversed_line.curve.add_point(Vector3(4, 0, 0))
	reversed_line.curve.add_point(Vector3.ZERO)
	add_child_autofree(reversed_line)

	move._line = forward_line
	var tangent_forward: Vector3 = forward_line.sample(0.0)["tangent"]
	var yaw_forward: float = LineWalkMove.yaw_of(tangent_forward) \
		+ deg_to_rad(move._yaw_offset(tangent_forward))

	move._line = reversed_line
	var tangent_reversed: Vector3 = reversed_line.sample(0.0)["tangent"]
	var yaw_reversed: float = LineWalkMove.yaw_of(tangent_reversed) \
		+ deg_to_rad(move._yaw_offset(tangent_reversed))

	var facing_forward := Vector3(-sin(yaw_forward), 0.0, -cos(yaw_forward))
	var facing_reversed := Vector3(-sin(yaw_reversed), 0.0, -cos(yaw_reversed))
	assert_almost_eq(facing_forward.x, facing_reversed.x, 0.001,
		"reversing the curve's point order flipped which way the body faces")
	assert_almost_eq(facing_forward.z, facing_reversed.z, 0.001,
		"reversing the curve's point order flipped which way the body faces")

# --- A/D are the body's own left and right, in both views ------------------
#
# The third-person camera sits behind the view, and the view is held within
# the fan centred on the body's facing, so the body's right is screen right
# whichever way the body faces. Nothing flips.

func _enter_ledge_walk(player: Player) -> void:
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position - Vector3(5.0, 0.0, 0.0),
		player.global_position + Vector3(5.0, 0.0, 0.0))
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(_line),
		"test setup: the ledge's reach volume never registered the player")
	player.move_manager.start(Move.LEDGE_WALK)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"test setup: never entered the ledge walk")
	await step(20)  # past the magnet fade

func test_first_person_d_is_never_mirrored() -> void:
	# D reads as the body's own right exactly as project_input() returns it.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)
	var right: Vector3 = player.global_transform.basis.x
	var before: Vector3 = player.global_position
	_world["input"].state.move = Vector2(1.0, 0.0)  # D
	await step(10)
	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(right), 0.0,
		"D in first person did not move the body toward its own right")

# --- W/S: camera-assisted, latched the same way ------------------------------

func test_facing_straight_out_and_holding_w_does_nothing() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)
	# Actually facing out. The catch leaves the view wherever the approach
	# had it and lets the look fan ease it round, so "straight out" has to be
	# set, not assumed.
	_turn_view(player, 0.0)
	await step(1)
	var before: Vector3 = player.global_position
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(10)
	assert_almost_eq(player.global_position.distance_to(before), 0.0, 0.01,
		"W moved the body before the view ever turned off the ledge's normal")

func test_holding_w_with_the_view_turned_past_the_threshold_carries_the_body() -> void:
	# The owner's own scenario: a third-person player holds W and steers with
	# the camera for a whole ledge section.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	# Past LedgeWalkConfig.look_assist_angle_deg (45) and inside the shipped
	# +-54.93 degree look constraint. Driven directly rather than through
	# simulated mouse pixels: LedgeWalkConfig does not set
	# absolute_yaw_constraint, so apply_look()'s relative branch rate-limits
	# yaw_delta PER TICK rather than keeping a running total, and just holds
	# whatever player.rotation.y already is on a tick with zero look input --
	# which is exactly what setting it directly and then feeding zero input
	# relies on.
	_turn_view(player, 50.0)
	await step(1)
	var before: Vector3 = player.global_position
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(30)
	var moved: float = player.global_position.distance_to(before)
	assert_gt(moved, 0.1,
		"holding W with the view turned 50 degrees off the body's facing did not carry the body (%.3f m)"
			% moved)

## Turns the VIEW by `degrees` off the body's own frozen facing.
##
## Both halves are needed, and writing rotation.y alone is not enough:
## LedgeWalkConfig sets absolute_yaw_constraint, so apply_look() rebuilds the
## body's yaw every tick from the rig's captured reference plus its own running
## total. A test that writes only rotation.y has it overwritten on the next
## frame and measures a view that never turned.
func _turn_view(player: Player, degrees: float) -> void:
	player.camera_rig._look_relative_yaw = deg_to_rad(degrees)
	player.rotation.y = player.visual_yaw() + deg_to_rad(degrees)

func test_the_look_assist_latches_through_a_view_change_held_through_the_press() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	_turn_view(player, 50.0)
	await step(1)
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(10)
	var mid: Vector3 = player.global_position

	# Turn the view back under the threshold WHILE W is still held. A live
	# re-gate would stop the assist on the spot; the latch must not.
	_turn_view(player, 10.0)
	await step(10)
	var kept: float = player.global_position.distance_to(mid)
	assert_gt(kept, 0.05,
		"turning the view back under the threshold mid-press stopped the assist (%.3f m)" % kept)

	# Release and press again with the view now under the threshold: the gate
	# applies fresh.
	_world["input"].state.move = Vector2.ZERO
	await step(5)
	var before_fresh: Vector3 = player.global_position
	_world["input"].state.move = Vector2(0.0, 1.0)
	await step(15)
	assert_almost_eq(player.global_position.distance_to(before_fresh), 0.0, 0.01,
		"a fresh press with the view under the threshold was not re-gated (%.3f m)"
			% player.global_position.distance_to(before_fresh))

# --- leaving actually leaves, and jump is refused ---------------------------

func test_walking_off_a_ledge_end_does_not_re_catch() -> void:
	# The owner's own report: the ledge could not be left, because
	# LedgeWalkConfig inherited MoveConfig's neutral zero cooldown and the very
	# next grounded tick's catch_gate() passed again.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	# SHORT ON PURPOSE: 0.72 m/s (ground_speed * 0.10) crosses a 1 m ledge in
	# well under a second, so the walk-off happens inside a sane frame budget.
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position - Vector3(0.5, 0.0, 0.0),
		player.global_position + Vector3(0.5, 0.0, 0.0))
	await step(5)
	assert_true(player.interest_lines.has(_line),
		"test setup: the ledge's reach volume never registered the player")
	player.move_manager.start(Move.LEDGE_WALK)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"test setup: never entered the ledge walk")
	await step(20)  # past the magnet fade
	# Held the whole way, which is what defeated the release latch's own
	# push-toward bypass in the reported failure.
	_world["input"].state.move = Vector2(1.0, 0.0)
	await step(120)
	assert_ne(player.move_manager.current_name, Move.LEDGE_WALK,
		"holding a direction off the end never left the ledge")

func test_jump_is_refused_on_a_ledge() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(5)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"jump launched a body that has no footing to launch from")

func test_jump_is_refused_on_a_beam() -> void:
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
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the balance walk")
	await step(20)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(5)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"jump launched a body that has no footing to launch from")

# --- a ledge the capsule is wider than ---------------------------------------
#
# The capsule's radius is 0.4 m; the debug course's ledge puts its wall 0.34 m
# from the line, and a level author will do the same wherever a ledge is
# narrow. The wall must not eat the step -- see
# LineWalkMove._slide_along_geometry() for what it cost when it did.

## A 10 m ledge line running +X from 1.5 m behind the player, with a wall
## along its -Z side (the unrotated line's own front) whose face sits
## `wall_gap` from the line. The body faces +Z on it and D walks it toward -X,
## which is the line's start, 1.5 m away.
## `at_feet` puts the line 5 cm above the floor instead of at the capsule's
## centre, so walking off an end is a step onto the floor rather than a drop.
func _enter_ledge_walk_beside_a_wall(player: Player, wall_gap: float, at_feet: bool = false) -> void:
	var origin: Vector3 = player.global_position
	var line_y: float = origin.y
	if at_feet:
		line_y = origin.y - (player.standing_height() * 0.5 - 0.05)
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		Vector3(origin.x - 1.5, line_y, origin.z), Vector3(origin.x + 8.5, line_y, origin.z))
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = origin + Vector3(3.5, 1.0, -(wall_gap + 0.5))
	await step(5)
	player.move_manager.start(Move.LEDGE_WALK)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"test setup: never entered the ledge walk")
	await step(20)  # past the magnet fade

func test_a_ledge_walked_against_a_wall_is_left_at_the_lines_end() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk_beside_a_wall(player, 0.34)
	var end: Vector3 = _line.sample(0.0)["position"]
	_world["input"].state.move = Vector2(1.0, 0.0)  # D, toward the line's start
	var ticks: int = 0
	while player.move_manager.current_name == Move.LEDGE_WALK and ticks < 400:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"the ledge was never walked off its end")
	assert_almost_eq(player.global_position.x, end.x, 0.05,
		"the move ended with the body %.2f m short of the line's end"
			% absf(player.global_position.x - end.x))

func test_a_body_against_a_wall_stops_when_the_keys_are_released() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk_beside_a_wall(player, 0.34)
	_world["input"].state.move = Vector2(-1.0, 0.0)  # A, toward the long end
	await step(30)
	_world["input"].state.move = Vector2.ZERO
	await step(1)
	var released_at: Vector3 = player.global_position
	await step(20)
	assert_almost_eq(player.global_position.distance_to(released_at), 0.0, 0.005,
		"the body kept sliding %.3f m after every key was released"
			% player.global_position.distance_to(released_at))

## Bearing of the third-person camera round the line's outward normal (+Z
func _camera_bearing(player: Player) -> float:
	var to_camera: Vector3 = player.camera_rig.camera.global_transform.origin \
		- player.global_position
	to_camera.y = 0.0
	return rad_to_deg(Vector3(0.0, 0.0, 1.0).signed_angle_to(to_camera.normalized(), Vector3.UP))

## Points the view so the ORDINARY third-person camera, which sits opposite
func _aim_camera_at_bearing(player: Player, bearing_deg: float) -> void:
	var camera_dir: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, deg_to_rad(bearing_deg))
	var forward: Vector3 = -camera_dir
	player.rotation.y = atan2(-forward.x, -forward.z)

func test_the_head_pitch_is_the_ledges_own_in_third_person_only() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	assert_almost_eq(ledge.head_pitch_override(), deg_to_rad(ledge.cfg.head_pitch_deg), 0.001,
		"in third person the head's pitch is not the ledge's own dial")
	player.camera_rig.third_person = false
	assert_true(is_nan(ledge.head_pitch_override()),
		"in first person the ledge must leave the head's pitch to the eye")

# --- walking off an end and straight back in ---------------------------------
#
# The owner's report: walk a ledge end to end, leave, turn round, walk back
# in -- and fall straight through. Two guards were refusing the re-catch: a
# timed cooldown, and a release latch that measured "pushing toward the line"
# against its nearest point, which for a body standing beside a ledge is
# always sideways. See Player.line_ready() and LineWalkMove.exit().

func test_walking_off_a_ledge_end_and_straight_back_in_re_catches() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk_beside_a_wall(player, 0.34, true)
	_world["input"].state.move = Vector2(1.0, 0.0)  # D, toward the near end
	var ticks: int = 0
	while player.move_manager.current_name == Move.LEDGE_WALK and ticks < 400:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"test setup: the ledge was never walked off its end")
	# Straight back, with no pause at all -- the case a timer refuses.
	_world["input"].state.move = Vector2(-1.0, 0.0)  # A, back in
	var caught: bool = false
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.LEDGE_WALK:
			caught = true
			break
	assert_true(caught, "walking straight back onto the ledge was refused")
	# ...and it stays caught: not a flutter.
	await step(10)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"the re-catch let go again")

# --- which way the body faces is the view's call -----------------------------
#
# First person backs onto the wall; third person faces it; a view change
# mid-ledge turns the body round in place over LedgeWalkConfig.turn_time.
# See LedgeWalkMove's own header.

## Whether the visible model faces the line's wall (its own -Z).
func _model_faces_wall(player: Player) -> bool:
	var yaw: float = player.visual_yaw()
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return facing.dot(_line.front()) > 0.5

func test_first_person_backs_onto_the_wall() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)
	assert_false(_model_faces_wall(player),
		"in first person the body must have its back to the wall")

func test_third_person_faces_the_wall() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	assert_true(_model_faces_wall(player),
		"in third person the body must face the wall")

func test_switching_to_first_person_mid_ledge_turns_the_body_round() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	_world["input"].state.move = Vector2(1.0, 0.0)  # D, and held throughout
	await step(10)

	player.camera_rig.third_person = false
	await step(2)
	assert_true(ledge.is_turning(), "switching the view did not start a turn")
	assert_almost_eq(ledge.scripted_duration(), ledge.cfg.turn_time, 0.001,
		"the turn did not offer its clip the window to fit")
	assert_true(String(ledge.turn_clip()).begins_with("Turn180_"),
		"the turn did not ask for the pack's half turn")
	# The feet are busy: no travel while turning, however hard D is held.
	var mid: Vector3 = player.global_position
	await step(5)
	assert_almost_eq(player.global_position.distance_to(mid), 0.0, 0.001,
		"the body kept shuffling while turning round")

	await step(int(ledge.cfg.turn_time * 60.0) + 5)
	assert_false(ledge.is_turning(), "the turn never ended")
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"turning round left the ledge")
	assert_false(_model_faces_wall(player),
		"after switching to first person the body still faces the wall")
	# ...and the shuffle resumes on the same held key.
	var after: Vector3 = player.global_position
	await step(15)
	assert_gt(player.global_position.distance_to(after), 0.05,
		"travel did not resume once the turn was done")

func test_switching_to_third_person_mid_ledge_turns_the_body_to_face_the_wall() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	player.camera_rig.third_person = true
	await step(int(ledge.cfg.turn_time * 60.0) + 8)
	assert_false(ledge.is_turning(), "the turn never ended")
	assert_true(_model_faces_wall(player),
		"after switching to third person the body still has its back to the wall")

func test_the_turn_goes_toward_the_side_the_view_is_on() -> void:
	# Looking left when the view switches, the body turns left; looking
	# right, right. The owner: a body that always turned the same way looked
	# wrong half the time.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)  # first person, back to the wall
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove

	_turn_view(player, 30.0)  # left of the body's facing
	await step(1)
	player.camera_rig.third_person = true
	await step(2)
	assert_true(ledge.is_turning(), "test setup: no turn began")
	assert_eq(String(ledge.turn_clip()), "Turn180_L",
		"looking left, the body turned the other way (%s)" % String(ledge.turn_clip()))
	await step(int(ledge.cfg.turn_time * 60.0) + 8)
	assert_false(ledge.is_turning(), "the turn never ended")

	_turn_view(player, -30.0)  # right of the NEW facing
	await step(1)
	player.camera_rig.third_person = false
	await step(2)
	assert_true(ledge.is_turning(), "test setup: the second turn never began")
	assert_eq(String(ledge.turn_clip()), "Turn180_R",
		"looking right, the body turned the other way (%s)" % String(ledge.turn_clip()))

func test_the_head_keeps_its_world_direction_through_a_turn() -> void:
	# A step to the body's right becomes a step to its left once it has
	# turned round; the direction the head watches is a direction in the
	# world, and must not flip with the body.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	_world["input"].state.move = Vector2(1.0, 0.0)  # D
	await step(10)
	_world["input"].state.move = Vector2.ZERO
	await step(2)
	var before: int = ledge._last_shuffle
	assert_ne(before, 0, "test setup: the body never travelled")
	player.camera_rig.third_person = false
	await step(2)
	assert_eq(ledge._last_shuffle, -before,
		"turning round did not carry the watched direction into the new body frame")

func test_third_person_looks_through_its_own_wider_fan() -> void:
	# The confirmed +-54.93 was measured through the original's eye; an
	# outside camera gets LedgeWalkConfig.third_person_look_yaw_deg instead,
	# and switching views swaps the fan on the spot.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk(player)
	var rig: CameraRig = player.camera_rig
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	assert_almost_eq(rig._look_max.y, ledge.cfg.max_look_constraint.y, 0.001,
		"first person is not looking through the confirmed fan")
	player.camera_rig.third_person = true
	await step(2)
	assert_almost_eq(rig._look_max.y, deg_to_rad(ledge.cfg.third_person_look_yaw_deg) * 0.5, 0.001,
		"third person is not looking through its own fan")
	assert_almost_eq(rig._look_min.y, -rig._look_max.y, 0.001, "the third-person fan is lopsided")

func test_the_shoulder_slides_to_the_centre_on_the_ledge_and_back_out_after() -> void:
	# Facing the wall with the camera out on the wall-side shoulder puts the
	# camera in the wall before the view has turned far at all. The ledge
	# asks for the centre (MoveConfig.centre_shoulder) and the rig slides
	# there on its own shoulder-cycle ease -- and slides back out on leaving.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await step(20)
	var rig: CameraRig = player.camera_rig
	var out: float = rig._shoulder_across
	assert_gt(absf(out), 0.1, "test setup: no shoulder offset to centre")
	var feet: Vector3 = player.global_position \
		- Vector3.UP * (player.standing_height() * 0.5 - 0.05)
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		feet - Vector3(8.5, 0.0, 0.0), feet + Vector3(1.5, 0.0, 0.0))
	await step(5)
	player.move_manager.start(Move.LEDGE_WALK)
	await step(1)
	# Eased, not cut: somewhere strictly between where it was and the centre.
	assert_gt(absf(rig._shoulder_across), 0.0,
		"the shoulder cut to the centre on the tick the ledge was caught")
	assert_lt(absf(rig._shoulder_across), absf(out),
		"the shoulder did not start sliding to the centre")
	await step(int(player.config.camera.third_person_shoulder_time * 60.0) + 10)
	assert_almost_eq(rig._shoulder_across, 0.0, 0.01,
		"the shoulder never reached the centre on the ledge")
	# Off the far end and onto the floor: the shoulder comes back.
	_world["input"].state.move = Vector2(1.0, 0.0)  # D: facing the wall, the body's right is +X
	var ticks: int = 0
	while player.move_manager.current_name == Move.LEDGE_WALK and ticks < 400:
		await step(1)
		ticks += 1
	assert_ne(player.move_manager.current_name, Move.LEDGE_WALK,
		"test setup: the ledge was never walked off")
	_world["input"].state.move = Vector2.ZERO
	await step(int(player.config.camera.third_person_shoulder_time * 60.0) + 10)
	assert_almost_eq(absf(rig._shoulder_across), absf(out), 0.01,
		"leaving the ledge did not hand the shoulder back")

func test_a_key_held_through_leaving_one_catch_is_read_afresh_at_the_next() -> void:
	# The owner's report: walk off a ledge's end with W held, turn round, walk
	# back in still holding it -- caught, ejected on the first tick, caught
	# again two ticks later, for as long as the key stays down. The W assist
	# is latched on press, and the press that began on the previous ledge
	# had kept the sign that ledge resolved.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	await _enter_ledge_walk_beside_a_wall(player, 0.34, true)  # first person, near end 1.5 m to -X
	# View turned right of the facing (+Z): right is -X, along the line, so W
	# walks the body toward the near end and off it.
	_turn_view(player, -50.0)
	await step(1)
	_world["input"].state.move = Vector2(0.0, 1.0)  # W, and held throughout
	var ticks: int = 0
	while player.move_manager.current_name == Move.LEDGE_WALK and ticks < 400:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"test setup: W never walked the body off the far end")
	# Turn round to face back along the ledge and keep walking.
	player.rotation.y = LineWalkMove.yaw_of(Vector3(1.0, 0.0, 0.0))
	var caught_at: int = -1
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.LEDGE_WALK:
			caught_at = i
			break
	assert_true(caught_at >= 0, "test setup: walking back in never re-caught the ledge")
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	var offset_in: float = ledge.line_offset()
	await step(20)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"the re-catch let go again: the held key was read with the previous ledge's sign")
	assert_gt(ledge.line_offset(), offset_in + 0.05,
		"W did not carry the body back in along the ledge after the re-catch")

# --- the squeeze: a ledge goes where its line goes -------------------------
#
# [ME:INFERRED] from play: the original walks a runner along a ledge and
# THROUGH a gap between two walls. The capsule is 0.8 m across and the gaps
# are narrower, so a ledge that respects geometry stalls there -- the body is
# pushed out of the wall every tick and never travels.

## Two blocks with `gap` metres of air between them, straddling the line at x.
func _pinch(at: Vector3, gap: float) -> Array[StaticBody3D]:
	var made: Array[StaticBody3D] = []
	for side in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 3.0, 3.0)
		shape.shape = box
		body.add_child(shape)
		add_child_autofree(body)
		body.global_position = at + Vector3(0.0, 0.0, side * (gap * 0.5 + 0.5))
		made.append(body)
	return made

func _walk_a_ledge_through(gap: float, through: bool) -> float:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.config.ledge_walk.pass_through_geometry = through
	_line = _make_line(InterestLine.Kind.LEDGE_WALK,
		player.global_position - Vector3(5.0, 0.0, 0.0),
		player.global_position + Vector3(5.0, 0.0, 0.0))
	await step(5)
	# Both ways along the line: which side D travels depends on the curve's
	# point order, and the squeeze has to be in the way either way.
	_pinch(player.global_position + Vector3(1.2, 0.0, 0.0), gap)
	_pinch(player.global_position - Vector3(1.2, 0.0, 0.0), gap)
	await step(2)
	player.move_manager.start(Move.LEDGE_WALK)
	await step(20)
	var before: float = player.global_position.x
	_world["input"].state.move = Vector2(1.0, 0.0)
	# A ledge walks at a tenth of walking speed, so this is seconds of travel.
	await step(300)
	_world["input"].state.move = Vector2.ZERO
	return absf(player.global_position.x - before)

func test_a_ledge_squeezes_through_a_gap_narrower_than_the_body() -> void:
	# 0.5 m of air against a 0.8 m capsule.
	var travelled: float = await _walk_a_ledge_through(0.5, true)
	assert_gt(travelled, 2.0,
		"the body travelled %.2f m: it never got through the gap" % travelled)

func test_without_the_pass_a_narrow_gap_stops_the_walk() -> void:
	# The other half: the switch is what does it, not the geometry being thin.
	var travelled: float = await _walk_a_ledge_through(0.5, false)
	assert_lt(travelled, 2.0,
		"respecting geometry, the body still crossed %.2f m of a 0.5 m gap" % travelled)
