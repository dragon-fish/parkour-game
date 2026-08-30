extends ParkourTest

func _world() -> Dictionary:
	return TestWorld.build(get_tree(), MovementConfig.new())

func _run_up(world: Dictionary, ticks: int) -> void:
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in ticks:
		await step(1)

func test_turning_costs_banked_speed_energy() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	assert_gt(before, 6.5, "never banked a full budget")
	# A hard left: the wish direction swings 90 degrees in one tick.
	world["input"].state.move = Vector2(-1.0, 0.0)
	await step(1)
	var after: float = world["player"].speed_energy.energy
	assert_true(after < before - 3.0, "a 90 degree turn cost almost nothing (%f -> %f)" % [before, after])
	TestWorld.teardown(world)
	await step(1)

func test_running_straight_costs_nothing() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	for i in 60:
		await step(1)
	assert_gt(world["player"].speed_energy.energy, before - 0.01, \
		"running in a straight line bled energy")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_and_repressing_a_direction_is_not_a_turn() -> void:
	# wish_direction() returns the zero vector with no input. Treating the
	# transition through zero as a heading change would charge the player for
	# every momentary key release.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2.ZERO
	await step(1)
	world["input"].state.move = Vector2(0.0, 1.0)
	await step(1)
	# One tick of no input does bleed through ordinary decay, and the decay
	# curve is steepest the instant the player stops (see SpeedEnergy.decay()).
	# What matters is that it is nothing like a turn's own cost: a hard
	# 90-degree flick runs about 4.6.
	assert_gt(world["player"].speed_energy.energy, before - 0.7, \
		"passing through zero input was charged as a turn")
	TestWorld.teardown(world)
	await step(1)

func test_turning_in_the_air_is_free() -> void:
	# Turn cost is a ground mechanic: air_control is 0.025, so there is barely
	# any turning to charge for, and charging for it would double-punish a
	# jump the player is already committed to.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	world["input"].press_jump()
	await step(1)
	world["input"].release_jump()
	for i in 10:
		await step(1)
	var before: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2(-1.0, 0.0)
	for i in 10:
		await step(1)
	assert_almost_eq(world["player"].speed_energy.energy, before, 0.01, "turning in the air cost energy")
	TestWorld.teardown(world)
	await step(1)

func test_even_a_one_degree_turn_costs_something() -> void:
	# The defining property of this mechanic is that there is NO free
	# allowance -- the research searched the original's data for a
	# "costs nothing below N degrees" threshold and found none. The other
	# tests here only exercise 90 degrees (a hard turn) and 0 degrees
	# (straight running); neither would catch a stray dead-band guard like
	# `if radians < deg_to_rad(1.0): return` slipped into _charge_turn(), so
	# this pins a genuinely small nonzero angle directly.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	assert_gt(before, 6.5, "never banked a full budget")
	# Compared against a straight-ahead tick rather than demanding a net drop.
	# [ME:CONFIRMED 03 §3.2] Cost scales with angular rate, so a one-degree
	# nudge is cheap enough that the same tick's ordinary accumulation can
	# outrun it -- a slow turn barely costs anything, which is the measured
	# behaviour, not a missing charge. What must remain true is that the
	# turning tick banks LESS than the straight one.
	await step(1)
	var straight_gain: float = world["player"].speed_energy.energy - before
	var pivot: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2(0.0, 1.0).rotated(deg_to_rad(1.0))
	await step(1)
	var turned_gain: float = world["player"].speed_energy.energy - pivot
	assert_true(turned_gain < straight_gain, 		"a one degree turn cost nothing (straight %f vs turned %f)" 		% [straight_gain, turned_gain])
	TestWorld.teardown(world)
	await step(1)

func test_turn_cost_wraps_correctly_across_180_degrees() -> void:
	# signed_angle_to()'s [-PI, PI] range means a wish direction flipping from
	# just past +180 degrees to just past -180 degrees is a ~2 degree turn,
	# not a ~358 degree one. Purely a regression guard -- confirmed correct
	# by inspection, since Godot's own signed_angle_to already handles the
	# wraparound -- but cheap next to a wraparound bug silently emptying the
	# whole energy budget on a barely-perceptible turn.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	# Swing to just past +180 degrees from straight ahead. This is itself a
	# near-maximal reversal and drains the budget close to zero -- that is
	# incidental setup cost, not what this test is about.
	world["input"].state.move = Vector2(0.0, 1.0).rotated(deg_to_rad(179.0))
	await step(1)
	# Hold that heading long enough to settle. It does NOT rebank to a full
	# budget: 179 degrees is running backwards, which drains to the base-speed
	# floor and stays there (Player._update_speed_energy()). The floor is
	# still a cushion with something to lose -- a wraparound read as a
	# near-full-lap turn would take it to nothing.
	for i in 180:
		await step(1)
	var before: float = world["player"].speed_energy.energy
	assert_gt(before, 0.3, "did not settle above the floor, so the check proves nothing")
	# Flip to just past -180 degrees -- a real turn of about 2 degrees.
	world["input"].state.move = Vector2(0.0, 1.0).rotated(deg_to_rad(-179.0))
	await step(1)
	var after: float = world["player"].speed_energy.energy
	var drop: float = before - after
	assert_true(drop < 0.5, \
		"a near-180-to-near-180 flip (really a ~2 degree turn) drained %f energy -- wraparound bug?" % drop)
	TestWorld.teardown(world)
	await step(1)

func test_landing_after_an_airborne_turn_only_bills_the_landing_ticks_own_turn() -> void:
	# THIS PINS BEHAVIOUR THE PROJECT HAS ALREADY ACKNOWLEDGED IS WRONG --
	# see docs/feel-backlog.md item 1. Turning hard mid-air and holding it
	# through landing currently costs nothing at all, because
	# _update_speed_energy() reads wish_direction() BEFORE the grounded
	# check, so _last_wish_dir tracks the wish continuously through the
	# whole flight (updated every tick, even while airborne) rather than
	# freezing at take-off. The landing tick then only ever compares against
	# the immediately preceding (airborne) wish, not the pre-jump heading, so
	# there is nothing left to bill. DO NOT strengthen this assertion to
	# demand a real cost -- fix the underlying mechanic first, then overturn
	# this test as part of that fix.
	#
	# What this test DOES guard, and should keep guarding even after the bug
	# above is fixed: `wish := wish_direction(input)` must stay outside the
	# grounded branch. Moving it back inside would leave _last_wish_dir stale
	# at the pre-jump heading for the whole flight, so landing after an
	# airborne turn would bill the FULL swing since take-off in one lump --
	# a different and strictly worse bug than the one this currently pins.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	assert_gt(player.speed_energy.energy, 6.5, "never banked a full budget")

	input.press_jump()
	await step(1)
	input.release_jump()
	assert_true(player.move_manager.current_name == Move.JUMP, "the jump did not leave the ground")

	# Turn hard while airborne and hold it -- free per
	# test_turning_in_the_air_is_free, but this is the state _last_wish_dir
	# must track through to the landing tick. Airborne spans both Jump and
	# Falling, so "landed" means back to Walking, not merely "no longer
	# Falling".
	input.state.move = Vector2(-1.0, 0.0)
	var energy_before_landing: float = player.speed_energy.energy
	var landed := false
	for i in 200:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			landed = true
			break
		energy_before_landing = player.speed_energy.energy
	assert_true(landed, "never observed a landing -- test setup is wrong")
	var drop: float = energy_before_landing - player.speed_energy.energy
	assert_true(drop < 1.0, \
		"landing after an airborne turn billed a near-full-budget turn (dropped %f)" % drop)
	TestWorld.teardown(world)
	await step(1)

func test_a_fast_flick_costs_more_per_degree_than_a_slow_pan() -> void:
	# [ME:CONFIRMED 03 §3.2] The original charges per degree AND scales that
	# rate with angular velocity, so a lazy sweep and a panicked flick
	# through the same angle are NOT the same price. Without this, planning
	# a line buys the player nothing.
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	var angle: float = deg_to_rad(30.0)

	energy.energy = 100.0
	energy.spend_turn(angle, 30.0 / 95.0)          # swung at ~95 deg/s
	var slow_cost: float = 100.0 - energy.energy

	energy.energy = 100.0
	energy.spend_turn(angle, 30.0 / 1050.0)        # the same 30 degrees, flicked
	var fast_cost: float = 100.0 - energy.energy

	assert_gt(fast_cost, slow_cost * 3.0, "a flick cost barely more than a pan")
	# [ME:CONFIRMED 03 §3.2] Measured ratio across the band is 5.54x (0.0167
	# -> 0.0926 per degree).
	assert_almost_eq(fast_cost / slow_cost, 5.55, 0.2, "the rate gradient is not the measured one")

func test_the_multiplier_is_clamped_outside_the_measured_band() -> void:
	# Beyond the measured band the shape is unknown; extrapolating a power law
	# there would invent a cost nobody observed. A one-tick 90-degree snap
	# reports ~5400 deg/s and must simply pay the fastest measured rate.
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	var fastest: float = pawn.turn_rate_cost_curve[pawn.turn_rate_cost_curve.size() - 1].y
	assert_almost_eq(energy.turn_rate_multiplier(5400.0), fastest, 0.0001, \
		"an impossibly fast turn was extrapolated past the measured band")
	assert_almost_eq(energy.turn_rate_multiplier(1.0), pawn.turn_rate_cost_curve[0].y, 0.0001, \
		"a crawl was extrapolated below the measured band")

func test_an_ordinary_turn_keeps_its_existing_calibration() -> void:
	# The curve is normalised to 1.0 at 450 deg/s so that adding it does not
	# silently retune every turn in the game -- only redistribute cost between
	# slow and fast ones.
	var pawn := PawnConfig.new()
	var energy := SpeedEnergy.new(pawn)
	assert_almost_eq(energy.turn_rate_multiplier(450.0), 1.0, 0.0001, \
		"the reference rate is no longer neutral")

func test_turning_never_bills_below_the_base_speed() -> void:
	# A hard flick must not be able to tax a runner all the way to a
	# standstill -- that reads as punishment rather than as a cost.
	#
	# [ME:INFERRED] However hard the view is swung, speed in the original
	# does not fall below roughly 16 km/h, and speed_max_base_velocity
	# (4.0 m/s, 14.4 km/h) is the one number in the speed block that
	# otherwise has no consumer -- close enough to the observed floor that
	# this is read as its intended purpose, not confirmed as such.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var player: Player = world["player"]
	var pawn := player.config.pawn
	assert_gt(player.speed_energy.energy, 6.5, "never banked a full budget")

	# Six full-speed flicks, far more than the budget could survive unfloored.
	for f in 6:
		for i in 6:
			world["input"].state.move = world["input"].state.move.rotated(deg_to_rad(30.0))
			await step(1)

	var floor_energy: float = SpeedEnergy.energy_for_speed(pawn, pawn.speed_max_base_velocity)
	assert_gt(player.speed_energy.energy, floor_energy - 0.001, \
		"turning drained past the base-speed floor (%.3f vs %.3f)" \
			% [player.speed_energy.energy, floor_energy])
	assert_gt(player.speed_cap(), pawn.speed_max_base_velocity - 0.01, \
		"the cap fell below base speed (%.2f m/s)" % player.speed_cap())

	TestWorld.teardown(world)
	await step(1)

func test_standing_still_still_empties_the_budget() -> void:
	# The floor is for TURNING only. Decay has to keep emptying the budget, or
	# standing still would leave the player permanently primed to run.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var player: Player = world["player"]
	world["input"].state.move = Vector2.ZERO
	for i in 400:
		await step(1)
	assert_almost_eq(player.speed_energy.energy, 0.0, 0.001, \
		"standing still did not empty the speed budget")

	TestWorld.teardown(world)
	await step(1)

func test_a_turn_taken_in_the_air_is_billed_on_landing() -> void:
	# Turning is not billed tick by tick in mid-air -- there is no traction to
	# lose speed through -- but a body that takes off facing one way and
	# lands facing another HAS turned, and must be billed for it on landing,
	# or a jump becomes a way to take a corner for free.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var player: Player = world["player"]
	assert_gt(player.speed_energy.energy, 6.5, "never banked a full budget")

	# Leave the ground, swing the body a half turn, come back down.
	world["input"].press_jump()
	await step(2)
	assert_true(not player.grounded, "test setup is wrong: never left the ground")
	world["input"].release_jump()
	player.rotate_y(PI)

	var before: float = player.speed_energy.energy
	for i in 120:
		await step(1)
		if player.grounded:
			break
	assert_true(player.grounded, "test setup is wrong: never landed")
	assert_true(player.speed_energy.energy < before - 0.5, \
		"a half turn taken in the air cost nothing on landing (%.3f -> %.3f)" \
			% [before, player.speed_energy.energy])

	TestWorld.teardown(world)
	await step(1)
