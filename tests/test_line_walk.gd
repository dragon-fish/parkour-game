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

# --- A/D: screen-relative in third person, latched on press -----------------
#
# The camera arc clamp keeps a third-person ledge view within the body's own
# front hemisphere the whole time (test_a_bearing_behind_the_body_clamps_...
# in test_camera_constraints.gd), and CameraRig never re-aims the camera at
# the body, so from that side raw body-relative D reads backwards on screen.
# This flips it -- and the flip must survive the camera changing mid-press.

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

func test_third_person_d_reads_as_the_bodys_left_and_holds_through_a_camera_change() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	await step(20)  # lets the arc clamp settle the camera into the front arc

	var right: Vector3 = player.global_transform.basis.x
	var before: Vector3 = player.global_position
	_world["input"].state.move = Vector2(1.0, 0.0)  # D
	await step(10)
	var displacement: Vector3 = player.global_position - before
	assert_lt(displacement.dot(right), 0.0,
		"D on a third-person ledge did not read as the body's own left")
	var ledge := player.move_manager.move_for(Move.LEDGE_WALK) as LedgeWalkMove
	assert_eq(ledge.shuffle_direction(), -1,
		"the mirrored travel was not reported to the animator as a step to the body's left")

	# Held the same key throughout: drop out of third person mid-press. A live
	# re-resolve would flip the travel direction straight back to normal; the
	# latch must not.
	player.camera_rig.third_person = false
	var mid: Vector3 = player.global_position
	await step(10)
	var still_flipped: Vector3 = player.global_position - mid
	assert_lt(still_flipped.dot(right), 0.0,
		"turning the camera mid-press changed which way D travelled")

	# Release and press again: a fresh press re-resolves against the new
	# camera state (now first person, so unflipped).
	_world["input"].state.move = Vector2.ZERO
	await step(5)
	var before_2: Vector3 = player.global_position
	_world["input"].state.move = Vector2(1.0, 0.0)
	await step(10)
	var after_release: Vector3 = player.global_position - before_2
	assert_gt(after_release.dot(right), 0.0,
		"a fresh press did not re-resolve against the camera state at the new press")

func test_first_person_d_is_never_mirrored() -> void:
	# No separate camera position exists in first person -- the eye IS the
	# view -- so there is nothing for the arc clamp to put in front, and D
	# must keep reading as the body's own right exactly as project_input()
	# returns it.
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
	var before: Vector3 = player.global_position
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(10)
	assert_almost_eq(player.global_position.distance_to(before), 0.0, 0.01,
		"W moved the body before the view ever turned off the body's own facing")

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
	player.rotation.y = player.visual_yaw() + deg_to_rad(50.0)
	await step(1)
	var before: Vector3 = player.global_position
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(30)
	var moved: float = player.global_position.distance_to(before)
	assert_gt(moved, 0.1,
		"holding W with the view turned 50 degrees off the body's facing did not carry the body (%.3f m)"
			% moved)

func test_the_look_assist_latches_through_a_view_change_held_through_the_press() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	await _enter_ledge_walk(player)
	player.rotation.y = player.visual_yaw() + deg_to_rad(50.0)
	await step(1)
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(10)
	var mid: Vector3 = player.global_position

	# Turn the view back under the threshold WHILE W is still held. A live
	# re-gate would stop the assist on the spot; the latch must not.
	player.rotation.y = player.visual_yaw() + deg_to_rad(10.0)
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
