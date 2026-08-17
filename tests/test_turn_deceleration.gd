class_name TestTurnDeceleration
extends TestCase

func _world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

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
	check_greater(before, 6.5, "never banked a full budget")
	# A hard left: the wish direction swings 90 degrees in one tick.
	world["input"].state.move = Vector2(-1.0, 0.0)
	await step(1)
	var after: float = world["player"].speed_energy.energy
	check(after < before - 3.0, "a 90 degree turn cost almost nothing (%f -> %f)" % [before, after])
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
	check_greater(world["player"].speed_energy.energy, before - 0.01, \
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
	# One tick of no input does bleed a little through ordinary decay, but it
	# must be nothing like a turn's own cost.
	check_greater(world["player"].speed_energy.energy, before - 0.5, \
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
	check_approx(world["player"].speed_energy.energy, before, 0.01, "turning in the air cost energy")
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
	check_greater(before, 6.5, "never banked a full budget")
	# Rotate the wish direction by exactly one degree off straight ahead.
	world["input"].state.move = Vector2(0.0, 1.0).rotated(deg_to_rad(1.0))
	await step(1)
	var after: float = world["player"].speed_energy.energy
	check(after < before, "a one degree turn cost nothing (%f -> %f)" % [before, after])
	TestWorld.teardown(world)
	await step(1)

func test_turn_cost_wraps_correctly_across_180_degrees() -> void:
	# signed_angle_to()'s [-PI, PI] range means a wish direction flipping from
	# just past +180 degrees to just past -180 degrees is a ~2 degree turn,
	# not a ~358 degree one. Purely a regression guard -- confirmed correct
	# by inspection, since Godot's own signed_angle_to already handles the
	# wraparound -- but cheap next to someone later re-deriving why a
	# barely-perceptible turn once emptied the whole energy budget.
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
	# Hold that heading (no further direction change, so no further turn
	# cost) long enough to rebank a meaningfully large energy cushion, so the
	# actual assertion below has something to lose if the wraparound were
	# read as a near-full-lap turn instead of a ~2 degree one.
	for i in 180:
		await step(1)
	var before: float = world["player"].speed_energy.energy
	check_greater(before, 0.5, "did not rebank enough energy for the wraparound check to be meaningful")
	# Flip to just past -180 degrees -- a real turn of about 2 degrees.
	world["input"].state.move = Vector2(0.0, 1.0).rotated(deg_to_rad(-179.0))
	await step(1)
	var after: float = world["player"].speed_energy.energy
	var drop: float = before - after
	check(drop < 0.5, \
		"a near-180-to-near-180 flip (really a ~2 degree turn) drained %f energy -- wraparound bug?" % drop)
	TestWorld.teardown(world)
	await step(1)

func test_landing_after_an_airborne_turn_only_bills_the_landing_ticks_own_turn() -> void:
	# _update_speed_energy() reads wish_direction() BEFORE the grounded
	# check, so _last_wish_dir tracks the wish continuously through the
	# whole flight, not just at take-off. That means the landing tick only
	# ever compares against the immediately preceding (airborne) wish, not
	# the pre-jump heading -- so turning hard mid-air and holding it costs
	# nothing extra on touchdown.
	#
	# This guards the exact regression the brief's own code shape calls out:
	# moving `wish := wish_direction(input)` back inside the grounded branch
	# would leave _last_wish_dir stale at the pre-jump heading for the whole
	# flight, and landing after an airborne turn would then bill the FULL
	# swing since take-off in one lump -- while every other test in this file
	# still passes, since none of them land after turning in the air.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	check_greater(player.speed_energy.energy, 6.5, "never banked a full budget")

	input.press_jump()
	await step(1)
	input.release_jump()
	check(player.move_manager.current_name == Move.FALLING, "the jump did not leave the ground")

	# Turn hard while airborne and hold it -- free per
	# test_turning_in_the_air_is_free, but this is the state _last_wish_dir
	# must track through to the landing tick.
	input.state.move = Vector2(-1.0, 0.0)
	var energy_before_landing: float = player.speed_energy.energy
	var landed := false
	for i in 200:
		await step(1)
		if player.move_manager.current_name != Move.FALLING:
			landed = true
			break
		energy_before_landing = player.speed_energy.energy
	check(landed, "never observed a landing -- test setup is wrong")
	var drop: float = energy_before_landing - player.speed_energy.energy
	check(drop < 1.0, \
		"landing after an airborne turn billed a near-full-budget turn (dropped %f)" % drop)
	TestWorld.teardown(world)
	await step(1)
