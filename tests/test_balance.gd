extends ParkourTest

# STRUCTURAL PROPERTIES ONLY. The dials (base_wobble, beam_half_width, the lean
# and FOV limits) are judged by eye and carry no assertions -- see
# .claude/skills/tuning-dials-not-rules. NO DAMPING TERM is a structural
# invariant, not a dial, so it gets an assertion -- see
# test_the_free_pendulum_matches_the_undamped_closed_form below.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func test_lean_diverges_when_nobody_corrects() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.01, 0.0)
	var first := absf(move.lean())
	for i in 10:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_gt(absf(move.lean()), first,
		"an inverted pendulum with no correction must run away from its apex")
	move.free()

## Guards constraint 1 (NO DAMPING TERM) directly. The test above cannot: for
## a seed with zero rate, the sign of the acceleration stays positive for
## EVERY damping coefficient, so lean_rate keeps climbing regardless of how
## much energy a damping term removes -- it only climbs slower. Only a
## quantitative check against the exact undamped solution can tell the two
## apart.
##
## x'' = omega^2 * x, x(0) = lean0, x'(0) = 0 has the closed form
## x'(t) = lean0 * omega * sinh(omega * t). Any damping term pulls the
## measured rate BELOW that line; the semi-implicit Euler integration in
## integrate_lean() tracks it to within ~0.01% over this window on its own,
## which is what sets the tolerance below.
func test_the_free_pendulum_matches_the_undamped_closed_form() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	var lean0: float = 0.01
	move.seed_lean(lean0, 0.0)
	var dt: float = 1.0 / 60.0
	var ticks: int = 60
	for i in ticks:
		move.integrate_lean(dt, 0.0)
	var omega: float = 1.0 / move.cfg.divergence_time
	var t: float = ticks * dt
	var expected: float = lean0 * omega * sinh(omega * t)
	assert_almost_eq(move.lean_rate(), expected, expected * 0.01,
		"a damping term pulls lean_rate below the exact undamped solution lean0*omega*sinh(omega*t)")
	move.free()

func test_the_apex_is_stationary() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.0, 0.0)
	for i in 60:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_almost_eq(move.lean(), 0.0, 0.0001,
		"zero lean AND zero rate is the unstable equilibrium: it must sit still")
	move.free()

func test_a_standstill_entry_still_leans() -> void:
	var cfg := BalanceConfig.new()
	var lean := BalanceMove.entry_lean(cfg, 0.0, 7.2, 1)
	assert_gt(absf(lean), 0.0,
		"the owner measured that standing still on a beam still loses balance")

func test_entry_lean_grows_with_entry_speed() -> void:
	var cfg := BalanceConfig.new()
	var slow := absf(BalanceMove.entry_lean(cfg, 0.0, 7.2, 1))
	var fast := absf(BalanceMove.entry_lean(cfg, 7.2, 7.2, 1))
	assert_gt(fast, slow, "SpeedInfluence magnifies the ENTRY offset")

## Regression guard for enter()'s own ordering, not entry_lean() in isolation.
## LineWalkMove.enter() zeroes player.velocity (see its own note on why), so
## BalanceMove.enter() has to read entry_speed BEFORE calling super.enter().
## Move that read one line down and every entry measures a standstill --
## entry_speed_influence goes silently dead -- and
## test_entry_lean_grows_with_entry_speed above cannot see it: it drives the
## static entry_lean() directly and never calls enter() at all.
func test_enter_reads_entry_speed_before_super_zeroes_it() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	beam.position = player.global_position
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.velocity = Vector3.ZERO
	var still := BalanceMove.new()
	still.player = player
	still.config = player.config
	still.cfg = player.config.balance
	still.enter(Move.WALKING)
	var standstill_lean: float = absf(still.lean())
	still.free()

	player.velocity = Vector3(0.0, 0.0, -player.config.pawn.ground_speed)
	var fast := BalanceMove.new()
	fast.player = player
	fast.config = player.config
	fast.cfg = player.config.balance
	fast.enter(Move.WALKING)
	var fast_lean: float = absf(fast.lean())
	fast.free()

	assert_gt(fast_lean, standstill_lean,
		"entry_speed must survive super.enter()'s velocity zeroing, or SpeedInfluence goes dead")

func test_correction_opposes_the_lean() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.05, 0.0)
	var free := move.duplicate_lean_after(0.2, 0.0)
	var corrected := move.duplicate_lean_after(0.2, -1.0)
	assert_lt(corrected, free, "A/D must fight the lean, not steer")
	move.free()

func test_entering_the_beam_from_its_start_walks_toward_the_far_end() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	# The player sits at local offset 0 -- the curve's own start.
	beam.position = player.global_position
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	# A run-up AT the far end: arriving at the start moving toward +X, the
	# same direction the curve's own tangent already points.
	player.velocity = Vector3(player.config.pawn.ground_speed, 0.0, 0.0)
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the beam")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	move.seed_lean(0.0, 0.0)  # isolate travel from the random entry wobble
	await step(5)  # past the magnet fade
	var before: Vector3 = player.global_position
	var forward: Vector3 = -player.global_transform.basis.z
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(30)
	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(forward), 0.0,
		"W did not move the body toward its own forward")
	assert_gt(displacement.x, 0.0,
		"entering at the start moving toward +X did not carry the body on toward the far end")

	# Correction: a lean seeded toward the body's own right must be fought by
	# the body-relative correction key (A), not by a world-fixed one.
	var lean0: float = 0.05
	move.seed_lean(lean0, 0.0)
	var free: float = move.duplicate_lean_after(0.2, 0.0)
	_world["input"].state.move = Vector2(-1.0, 0.0)  # A
	for i in 12:  # 0.2s at the suite's fixed 60 fps
		await step(1)
	assert_lt(absf(move.lean()), free,
		"A did not fight a lean seeded while entering from the beam's start")

func test_entering_the_beam_from_its_far_end_walks_toward_the_start_end() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	# The player sits at local offset 10 -- the curve's own far end -- by
	# shifting the line's origin back instead of touching the curve itself
	# (the curve's own drawing direction, +X, must stay the same as the test
	# above; only WHERE the player meets it changes).
	beam.position = player.global_position - Vector3(10.0, 0.0, 0.0)
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	# A run-up AT the start end: arriving at the far end moving toward -X,
	# AGAINST the curve's own tangent.
	player.velocity = Vector3(-player.config.pawn.ground_speed, 0.0, 0.0)
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the beam")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	move.seed_lean(0.0, 0.0)
	await step(5)  # past the magnet fade
	var before: Vector3 = player.global_position
	var forward: Vector3 = -player.global_transform.basis.z
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(30)
	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(forward), 0.0,
		"W did not move the body toward its own forward")
	assert_lt(displacement.x, 0.0,
		"entering at the far end moving toward -X did not carry the body on toward the start end")

	var lean0: float = 0.05
	move.seed_lean(lean0, 0.0)
	var free: float = move.duplicate_lean_after(0.2, 0.0)
	_world["input"].state.move = Vector2(-1.0, 0.0)  # A
	for i in 12:
		await step(1)
	assert_lt(absf(move.lean()), free,
		"A did not fight a lean seeded while entering from the beam's far end")

func test_the_ledge_walk_has_no_pendulum() -> void:
	var move := LedgeWalkMove.new()
	assert_false(move.has_method("lean"),
		"LedgeWalk carries none of TdMove_Balance's five pendulum fields")
	move.free()

## Falling off is GEOMETRIC: the same lateral_offset() the camera/skeleton/HUD
## read is what lateral_update() compares against beam_half_width. Needs a
## real Player because lateral_update() calls player.consume_roll() on the
## way out -- not a second, independent threshold check.
func test_falling_off_the_beam_is_geometric() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	var player: Player = _world["player"]
	var move := BalanceMove.new()
	move.player = player
	move.config = player.config
	move.cfg = BalanceConfig.new()
	# A lean whose real lateral displacement (lean * gravity_influence)
	# already clears the beam's half width.
	var over_the_edge: float = (move.cfg.beam_half_width / move.cfg.gravity_influence) + 0.1
	move.seed_lean(over_the_edge, 0.0)
	var result: StringName = move.lateral_update(1.0 / 60.0, 0.0)
	assert_eq(result, Move.FALLING,
		"past the beam's half width the feet have nothing under them")
	move.free()

## Constraint 3 (the lean is REAL lateral displacement, not one more
## threshold check): lateral_offset() must actually reach global_position
## through LineWalkMove.physics_update()'s `stand` calculation, not merely be
## a number lateral_update() compares against beam_half_width in isolation.
## Deleting the "+ lateral_offset() * _normal_at(_walk_yaw)" term there keeps
## every other test in this file green.
func test_the_lean_displaces_the_body_off_the_centreline() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	beam.position = player.global_position
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the move manager did not enter Balance")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	# Zero out the random entry lean so the body settles dead on the
	# centreline before the sub-edge lean below is seeded.
	move.seed_lean(0.0, 0.0)
	await step(5)  # past the magnet fade
	var before: Vector3 = player.global_position
	var right: Vector3 = player.global_transform.basis.x

	# Sub-edge: well under beam_half_width in real displacement, so
	# lateral_update() keeps returning KEEP and the body stays on the beam.
	var lean: float = move.cfg.beam_half_width / move.cfg.gravity_influence * 0.5
	move.seed_lean(lean, 0.0)
	await step(3)

	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(right) * signf(move.lateral_offset()), 0.0,
		"seeding a sub-edge lean did not move the body off the centreline in the direction lateral_offset() reports")

## Drives a REAL transition through MoveManager.start() -- calling
## set_balance_lean(0.0, 0.0) directly on a rig proves the rig responds to
## zeros (already covered by test_camera_constraints.gd) but never proves
## exit() is what SENDS them.
## Deleting BalanceMove.exit()'s body must fail this test; it cannot fail a
## test that never calls exit() at all -- see LadderMove.exit()'s own tint
## reset for the precedent this follows.
func test_exiting_the_move_zeroes_the_camera_lean() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	beam.position = player.global_position
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the move manager did not enter Balance")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	# Half the beam's own width -- enough lean for a non-zero roll and squeeze
	# without tripping the FALLING transition lateral_update() would return.
	move.seed_lean(move.cfg.beam_half_width / move.cfg.gravity_influence * 0.5, 0.0)
	move.lateral_update(1.0 / 60.0, 0.0)

	var rig: CameraRig = player.camera_rig
	assert_gt(absf(rig._balance_roll), 0.0,
		"test setup: the lean produced no roll for the camera to carry")
	assert_gt(rig._balance_squeeze, 0.0,
		"test setup: the lean produced no squeeze for the camera to carry")

	# A real transition, not a direct call -- exit() is under test, not the
	# rig's own response to zeros.
	player.move_manager.start(Move.WALKING)
	assert_almost_eq(rig._balance_roll, 0.0, 0.0001,
		"leaving Balance left the camera roll behind")
	assert_almost_eq(rig._balance_squeeze, 0.0, 0.0001,
		"leaving Balance left the FOV squeeze behind")
