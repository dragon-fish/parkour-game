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
	# The wind is the beam's own randomness, not the pendulum's -- silenced
	# here so this measures the arithmetic it names.
	# test_the_wind_moves_a_body_that_is_doing_nothing covers the wind itself.
	move.cfg.wind_strength = 0.0
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
	# The wind is the beam's own randomness, not the pendulum's -- silenced
	# here so this measures the arithmetic it names.
	# test_the_wind_moves_a_body_that_is_doing_nothing covers the wind itself.
	move.cfg.wind_strength = 0.0
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
	# The wind is the beam's own randomness, not the pendulum's -- silenced
	# here so this measures the arithmetic it names.
	# test_the_wind_moves_a_body_that_is_doing_nothing covers the wind itself.
	move.cfg.wind_strength = 0.0
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
	# EXITED, not merely freed. enter() applies a forced-view status that names
	# this move as its source, and a move freed without exiting leaves that
	# status behind holding a dangling reference -- the next enter() then trips
	# StatusList's own conflict check against a freed object.
	still.exit()
	still.free()

	player.velocity = Vector3(0.0, 0.0, -player.config.pawn.ground_speed)
	var fast := BalanceMove.new()
	fast.player = player
	fast.config = player.config
	fast.cfg = player.config.balance
	fast.enter(Move.WALKING)
	var fast_lean: float = absf(fast.lean())
	fast.exit()
	fast.free()

	assert_gt(fast_lean, standstill_lean,
		"entry_speed must survive super.enter()'s velocity zeroing, or SpeedInfluence goes dead")

func test_correction_opposes_the_lean() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	# The wind is the beam's own randomness, not the pendulum's -- silenced
	# here so this measures the arithmetic it names.
	# test_the_wind_moves_a_body_that_is_doing_nothing covers the wind itself.
	move.cfg.wind_strength = 0.0
	move.seed_lean(0.05, 0.0)
	var free := move.duplicate_lean_after(0.2, 0.0)
	var corrected := move.duplicate_lean_after(0.2, -1.0)
	assert_lt(corrected, free, "A/D must fight the lean, not steer")
	move.free()

# --- bidirectional entry: which way the body walks is decided by how the
# player arrived, not by the curve's own fixed drawing direction. Two ends,
# each entered from a run-up pointed AT it, must each send the body on to the
# OPPOSITE end, and the correction key must fight a seeded lean the same way
# regardless of which end that was. -----------------------------------------

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
	# And from the wind: the correction check below compares this ride
	# against duplicate_lean_after(), and two rides under two random gusts
	# differ by more than a fifth of a second of correction.
	move.cfg.wind_strength = 0.0
	await step(5)  # past the magnet fade
	var before: Vector3 = player.global_position
	var forward: Vector3 = _model_forward(player)
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
	move.cfg.wind_strength = 0.0  # see the twin test above
	await step(5)  # past the magnet fade
	var before: Vector3 = player.global_position
	var forward: Vector3 = _model_forward(player)
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

# --- forced first person: the beam is not third-person eligible, whatever the
# player's own saved preference. BEAM ONLY -- LedgeWalkMove keeps the
# player's own view choice, so it gets its own guard test below rather than
# sharing the machinery. ------------------------------------------------

func _make_balance_beam(player: Player) -> InterestLine:
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	beam.position = player.global_position
	return beam

func test_entering_the_beam_forces_first_person_over_the_saved_preference() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	var beam := _make_balance_beam(player)
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the move manager did not enter Balance")
	await step(1)
	assert_false(player.camera_rig.in_third_person(),
		"the beam did not force first person over the player's saved third-person preference")
	# THE PREFERENCE ITSELF MUST SURVIVE, not merely be overridden --
	# see test_status_forced_view.gd's own test of this same distinction for
	# the status mechanism in general.
	assert_true(player.camera_rig.third_person,
		"forcing the view overwrote the saved preference instead of merely overriding it")

## Drives a REAL transition through MoveManager.start(), the same shape
## test_exiting_the_move_zeroes_the_camera_lean above uses -- deleting
## BalanceMove.exit()'s status removal must fail this test; it cannot fail a
## test that never calls exit() at all.
func test_leaving_the_beam_restores_the_saved_preference() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	var beam := _make_balance_beam(player)
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the move manager did not enter Balance")
	await step(1)
	assert_false(player.camera_rig.in_third_person(),
		"test setup: the beam did not force first person")

	player.move_manager.start(Move.WALKING)
	await step(1)
	assert_true(player.camera_rig.in_third_person(),
		"leaving the beam left the forced first person behind")

## Exercises the WALKING exit path with real per-tick input rather than a
## forced move_manager.start(), on a beam short enough that a few ticks of W
## clears it.
func test_walking_off_the_beams_end_restores_the_saved_preference() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(0.5, 0.0, 0.0))  # short: a handful of ticks of W clears it
	beam.position = player.global_position
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the move manager did not enter Balance")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	move.seed_lean(0.0, 0.0)  # isolate travel from the random entry wobble
	await step(5)  # past the magnet fade
	assert_false(player.camera_rig.in_third_person(),
		"test setup: the beam did not force first person")

	_world["input"].state.move = Vector2(0.0, 1.0)  # W, straight off the end
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"test setup: walking never reached the beam's own end")
	# _push_forced_view() reads the STATUS LIST one tick before the moves run
	# (see its own note in player.gd), so the exit() that just removed the
	# status this tick is not reflected in camera_rig.forced_view until the
	# NEXT tick's push.
	await step(1)
	assert_true(player.camera_rig.in_third_person(),
		"walking off the beam's end left the forced first person behind")

## Exercises the FALLING exit path via the real per-tick loop discovering an
## over-edge lean, the same seed test_falling_off_the_beam_is_geometric uses --
## but let MoveManager transition on its own instead of reading
## lateral_update()'s return value by hand, since exit() only runs on a
## genuine transition.
func test_losing_balance_restores_the_saved_preference() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	var beam := _make_balance_beam(player)
	add_child_autofree(beam)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the move manager did not enter Balance")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	await step(5)  # past the magnet fade
	assert_false(player.camera_rig.in_third_person(),
		"test setup: the beam did not force first person")

	var over_the_edge: float = move.fall_lean() + 0.1
	move.seed_lean(over_the_edge, 0.0)
	# The capsule is carried off the line over fall_push_time before the
	# handover -- losing balance is a shove, not a teleport.
	await step(int(move.cfg.fall_push_time * 60.0) + 10)
	# Off the beam is all that matters here; on this floor-height fixture the
	# shove's drop lands the body straight away, so the move may already be
	# past FALLING.
	assert_ne(player.move_manager.current_name, Move.BALANCE,
		"test setup: the over-edge lean did not fall the player off the beam")
	# See the identical note in test_walking_off_the_beams_end_restores_the_
	# saved_preference above: the push that reflects this tick's exit() lands
	# on the NEXT tick.
	await step(1)
	assert_true(player.camera_rig.in_third_person(),
		"losing balance and falling off left the forced first person behind")

func test_the_ledge_walk_does_not_force_the_view() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	var ledge := InterestLine.new()
	ledge.kind = InterestLine.Kind.LEDGE_WALK
	ledge.curve = Curve3D.new()
	ledge.curve.add_point(Vector3.ZERO)
	ledge.curve.add_point(Vector3(10.0, 0.0, 0.0))
	ledge.position = player.global_position
	add_child_autofree(ledge)
	await step(5)  # lets the reach volume's Area3D register the overlap
	assert_true(player.interest_lines.has(ledge),
		"test setup: the ledge's reach volume never registered the player")

	player.move_manager.start(Move.LEDGE_WALK)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK,
		"test setup: the move manager did not enter LedgeWalk")
	await step(1)
	assert_true(player.camera_rig.in_third_person(),
		"the ledge walk touched the player's own view choice -- that is BalanceMove's job alone")

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
	# A lean past the point where the feet run out of beam.
	move.seed_lean(move.fall_lean() + 0.1, 0.0)
	# The first tick starts the shove; the handover comes once it has carried
	# the capsule clear, which is what makes the fall geometric rather than a
	# counter reaching a number.
	var result: StringName = move.lateral_update(1.0 / 60.0, 0.0)
	assert_eq(result, Move.KEEP,
		"losing balance handed over before the body had been moved anywhere")
	var ticks: int = 0
	while result == Move.KEEP and ticks < 120:
		result = move.lateral_update(1.0 / 60.0, 0.0)
		ticks += 1
	assert_eq(result, Move.FALLING,
		"past the beam's half width the feet have nothing under them")
	assert_gt(absf(move.lateral_offset()), 0.0,
		"the body was handed to the fall still sitting on the line")
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
	var right: Vector3 = _model_forward(player).cross(Vector3.UP)

	# Sub-edge: the ride keeps the capsule ON the line, whatever the lean is
	# doing. Sliding it sideways drags the visible model with it, which reads
	# as skating rather than wobbling -- the lean is carried by the camera roll
	# and the skeleton instead.
	var lean: float = move.fall_lean() * 0.5
	move.seed_lean(lean, 0.0)
	await step(3)
	var held: Vector3 = player.global_position - before
	assert_almost_eq(held.dot(right), 0.0, 0.02,
		"a lean short of the edge slid the capsule off the line")

	# Past the edge, the shove is the one thing that does move it, and it moves
	# it the way lateral_offset() reports.
	move.seed_lean(move.fall_lean() + 0.1, 0.0)
	await step(int(move.cfg.fall_push_time * 60.0) - 5)
	var displacement: Vector3 = player.global_position - before
	assert_gt(displacement.dot(right) * signf(move.lateral_offset()), 0.0,
		"losing balance never carried the body off the line")

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

	# The TARGETS: what the move asks for. The rig eases its own roll and
	# squeeze toward them (see CameraConfig.balance_recover_time), and that
	# ease is the rig's business, covered in test_camera_constraints.gd.
	var rig: CameraRig = player.camera_rig
	assert_gt(absf(rig._balance_roll_target), 0.0,
		"test setup: the lean produced no roll for the camera to carry")
	assert_gt(rig._balance_squeeze_target, 0.0,
		"test setup: the lean produced no squeeze for the camera to carry")

	# A real transition, not a direct call -- exit() is under test, not the
	# rig's own response to zeros.
	player.move_manager.start(Move.WALKING)
	assert_almost_eq(rig._balance_roll_target, 0.0, 0.0001,
		"leaving Balance left the camera roll behind")
	assert_almost_eq(rig._balance_squeeze_target, 0.0, 0.0001,
		"leaving Balance left the FOV squeeze behind")

func test_a_full_correction_at_the_edge_can_still_turn_the_lean_around() -> void:
	# The owner, in play: past a certain angle nothing the player did mattered.
	# The divergence term grows with the lean and a flat gain does not, so a
	# fixed correction is arithmetically overwhelmed somewhere short of the
	# edge. This pins that the boost puts the far end back within reach --
	# a structural property of the two curves, not a feel value.
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	# The wind is the beam's own randomness, not the pendulum's -- silenced
	# here so this measures the arithmetic it names.
	# test_the_wind_moves_a_body_that_is_doing_nothing covers the wind itself.
	move.cfg.wind_strength = 0.0
	var edge_lean: float = move.cfg.beam_half_width / move.cfg.gravity_influence
	# Just inside the edge, already falling, correcting at full strength.
	move.seed_lean(edge_lean * 0.97, 0.0)
	for i in 30:
		move.integrate_lean(1.0 / 60.0, -1.0)
	assert_lt(move.lean_rate(), 0.0,
		"a held full-strength correction at the edge never turned the lean around")
	move.free()

func test_the_correction_gain_only_grows_near_the_edge() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	var edge_lean: float = move.cfg.beam_half_width / move.cfg.gravity_influence
	assert_almost_eq(move.correction_gain_at(0.0), move.cfg.correction_gain, 0.0001,
		"the boost reached all the way back to the apex")
	assert_gt(move.correction_gain_at(edge_lean), move.correction_gain_at(edge_lean * 0.5),
		"the correction gained no authority on the way to the edge")
	move.free()

func test_the_wind_moves_a_body_that_is_doing_nothing() -> void:
	# The owner, in play: the original pushes the player about on a beam -- the
	# lean crosses sides with no warning and visibly jitters. A bare divergence
	# cannot do that; it only ever runs further from the apex it started on.
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.0, 0.0)
	for i in 240:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_ne(move.lean_rate(), 0.0,
		"a body sitting exactly on the apex was never moved off it")
	move.free()

func test_silencing_the_wind_leaves_the_apex_alone() -> void:
	# The wind is a dial, and zero must mean zero -- a pure pendulum for anyone
	# who wants to reason about the arithmetic without it.
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.cfg.wind_strength = 0.0
	move.seed_lean(0.0, 0.0)
	for i in 240:
		move.integrate_lean(1.0 / 60.0, 0.0)
	assert_eq(move.lean_rate(), 0.0,
		"a silenced wind still moved a body sitting on the apex")
	move.free()

func test_the_wind_fades_out_as_the_body_nears_the_edge() -> void:
	# The owner, in play: the pushes are strongest while the player is holding
	# it together and stop once the beam is nearly lost. The beam gives you
	# something to do while you are winning; it does not pile on while you are
	# trying to recover.
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	var edge_lean: float = move.cfg.beam_half_width / move.cfg.gravity_influence
	# Sampled rather than taken once: the wind's direction wanders, so only
	# the magnitude over many samples carries the property being asserted.
	var steady_total: float = 0.0
	var edge_total: float = 0.0
	for i in 400:
		move.seed_lean(0.0, 0.0)
		move._wind_phase += 0.37
		move.integrate_lean(1.0 / 60.0, 0.0)
		steady_total += absf(move.lean_rate())
		move.seed_lean(edge_lean * 0.98, 0.0)
		move._wind_phase += 0.37
		move.integrate_lean(1.0 / 60.0, 0.0)
		# The divergence term is enormous out here and would swamp the wind;
		# subtract the run it would have had on its own.
		var free_run: float = edge_lean * 0.98 \
			/ (move.cfg.divergence_time * move.cfg.divergence_time) * (1.0 / 60.0)
		edge_total += absf(move.lean_rate() - free_run)
	assert_gt(steady_total, edge_total,
		"the beam pushed a body about to fall as hard as one holding steady")
	move.free()

## Where the visible model faces -- the reference every "toward its own
## forward" claim in this file measures against. NOT the capsule's basis: this
## tier leaves the capsule to the view (see LineWalkMove's own note on why it
## stopped turning it), so the capsule's -Z is wherever the mouse was at the
## catch, not the beam.
func _model_forward(player: Player) -> Vector3:
	var yaw: float = player.visual_yaw()
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func test_backing_onto_the_beam_keeps_backing_along_it() -> void:
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
	await step(5)
	assert_true(player.interest_lines.has(beam),
		"test setup: the beam's reach volume never registered the player")

	# Facing -X and moving +X with S held: walking backwards onto the beam's
	# start, the key still down through the catch.
	player.rotation.y = LineWalkMove.yaw_of(Vector3(-1.0, 0.0, 0.0))
	player.velocity = Vector3(player.config.pawn.ground_speed, 0.0, 0.0)
	_world["input"].state.move = Vector2(0.0, -1.0)  # S
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the beam")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	move.seed_lean(0.0, 0.0)
	await step(30)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"S held through a backwards catch walked the body straight back off the end")
	assert_gt(move.line_offset(), 0.2,
		"S did not carry the body on along the beam (%.2f m)" % move.line_offset())

# --- the shove that ends the ride --------------------------------------------

func test_losing_balance_gives_the_view_back_the_tick_the_shove_starts() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = true
	var beam := _make_balance_beam(player)
	add_child_autofree(beam)
	await step(5)
	player.move_manager.start(Move.BALANCE)
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	await step(5)
	assert_false(player.camera_rig.in_third_person(),
		"test setup: the beam did not force first person")
	move.seed_lean(move.fall_lean() + 0.1, 0.0)
	# One tick starts the shove, the next reflects the status change -- see
	# the note in test_walking_off_the_beams_end_restores_the_saved_preference.
	await step(2)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: the shove handed over before it had carried the body anywhere")
	assert_true(player.camera_rig.in_third_person(),
		"the forced first person outlived the balance it was there for")

func test_the_shove_drops_the_body_and_hands_the_fall_its_own_speed() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	# Two metres up, body and beam both, so the fall the shove hands over to
	# has room to be a fall: with the beam at floor height the landing probe
	# catches the floor on the first airborne tick and the handover reads as
	# a step.
	player.global_position += Vector3.UP * 2.0
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(10.0, 0.0, 0.0))
	beam.position = player.global_position
	add_child_autofree(beam)
	await step(5)
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the beam")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	move.seed_lean(0.0, 0.0)
	await step(15)  # past the magnet fade, standing on the line
	var on_the_line: float = player.global_position.y
	move.seed_lean(move.fall_lean() + 0.1, 0.0)
	var ticks: int = 0
	while player.move_manager.current_name == Move.BALANCE and ticks < 120:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.FALLING,
		"the over-edge lean did not fall the player off the beam")
	assert_lt(player.global_position.y, on_the_line - move.cfg.fall_push_drop * 0.8,
		"the shove left the body at the beam's own height instead of beside and below it")
	# The fall has already added one tick of its own gravity, so the arc's
	# end speed must still be there underneath it.
	var arc_end_speed: float = 2.0 * move.cfg.fall_push_drop / move.cfg.fall_push_time
	assert_lt(player.velocity.y, -arc_end_speed * 0.9,
		"the fall started from rest after the shove (%.2f m/s, arc ends at %.2f)"
			% [player.velocity.y, -arc_end_speed])
	# Being thrown off is the one exit that arms the [ME:CONFIRMED] half-second
	# cooldown -- the body is still inside the volume for the first airborne
	# ticks, and the catch gate must not take it straight back.
	assert_false(player.move_manager.can_enter(Move.BALANCE),
		"losing balance left the beam ready to re-catch the falling body")

func test_walking_off_the_beams_end_and_straight_back_in_re_catches() -> void:
	# The owner's report: walk the beam end to end, leave, turn round, walk
	# back on -- and fall straight through, because the timed cooldown that
	# guards being thrown off was also refusing the walk back. See
	# LineWalkMove.exit() and Player.line_ready().
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	# At the feet, so walking off the end is a step onto the floor. Short, so
	# the walk-off is quick; entered at its middle.
	var feet: Vector3 = player.global_position 		- Vector3.UP * (player.standing_height() * 0.5 - 0.05)
	var beam := InterestLine.new()
	beam.kind = InterestLine.Kind.BALANCE
	beam.curve = Curve3D.new()
	beam.curve.add_point(Vector3.ZERO)
	beam.curve.add_point(Vector3(2.0, 0.0, 0.0))
	beam.position = feet - Vector3(1.0, 0.0, 0.0)
	add_child_autofree(beam)
	await step(5)
	player.rotation.y = LineWalkMove.yaw_of(Vector3(1.0, 0.0, 0.0))
	player.move_manager.start(Move.BALANCE)
	assert_eq(player.move_manager.current_name, Move.BALANCE,
		"test setup: never entered the beam")
	var move := player.move_manager.move_for(Move.BALANCE) as BalanceMove
	move.seed_lean(0.0, 0.0)
	move.cfg.wind_strength = 0.0
	_world["input"].state.move = Vector2(0.0, 1.0)  # W, to the far end
	var ticks: int = 0
	while player.move_manager.current_name == Move.BALANCE and ticks < 300:
		move.seed_lean(0.0, 0.0)
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"test setup: the beam was never walked off its end")
	_world["input"].state.move = Vector2(0.0, -1.0)  # S, straight back on
	var caught: bool = false
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.BALANCE:
			caught = true
			break
	assert_true(caught, "walking straight back onto the beam was refused")
