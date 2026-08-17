class_name TestFallingMoveIntegration
extends TestCase

# Drives a real Player through _physics_process(), not a hand-fed formula --
# both tests here exist because a review found bugs that only manifest under
# the REAL tick ordering (Player.fall_tracker.update() running before
# MoveManager each tick, FallingMove reading/resetting it around
# move_and_slide()), which nothing in test_fall_tracker.gd or
# test_landing_tiers.gd's hand-built Player stub could ever have caught.

const TestWorld = preload("res://tests/world_fixture.gd")

func _settle(world: Dictionary) -> void:
	# Let the player actually come to rest on the floor under real physics
	# (grounded declared, floor_snap settled) before a test starts messing
	# with its position.
	await step(10)

func test_a_short_landing_leaves_the_roll_buffer_for_the_slide() -> void:
	# Regression test for falling_move.gd's `rolled` expression having
	# consume_roll() as the LEFT operand of `and`: that unconditionally spends
	# the buffered press on every landing, threshold or not, leaving
	# walking_move.gd's slide-entry check nothing to read on the very next
	# tick. A landing well under skill_roll_landing_height (2.0 m) must NOT
	# consume the buffer -- the press has to survive to open the slide.
	var world := TestWorld.build(tree, MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await _settle(world)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Build up ground speed past slide_entry_speed (4.0) before leaving the
	# floor, same as a real player running and then stepping off a low ledge.
	input.state.move = Vector2(0.0, 1.0)
	for i in 90:
		await step(1)
	check_greater(player.horizontal_speed(), player.config.slide.slide_entry_speed, \
		"did not reach slide entry speed before the drop")

	# A small hop, well under the 2.0 m roll threshold.
	player.global_position.y += 1.0
	await step(1)
	check(player.move_manager.current_name == Move.FALLING, \
		"teleporting up did not send the player airborne")

	# Buffer the roll press while airborne, matching a player who pressed
	# crouch expecting to land into a slide.
	input.press_crouch()
	await step(1)
	input.release_crouch()

	var landed := false
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.WALKING and i > 0:
			landed = true
			break
	check(landed, "never returned to Walking after the short hop")
	check(player.last_landing_fall_height < player.config.pawn.skill_roll_landing_height, \
		"the drop was not actually below the roll threshold -- test setup is wrong")

	# The buffer must still be armed: one more tick of WalkingMove, still
	# moving fast, should open the slide.
	var opened_slide := false
	for i in 5:
		await step(1)
		if player.move_manager.current_name == Move.SLIDE:
			opened_slide = true
			break
	check(opened_slide, "the roll buffer was eaten by the short landing instead of surviving for the slide")

	TestWorld.teardown(world)
	await step(1)

func test_the_fall_counter_includes_the_landing_ticks_own_descent() -> void:
	# Regression test for fall_tracker.update() being called BEFORE
	# MoveManager runs each tick, so it only ever sees LAST tick's
	# velocity/position -- the descent that happens during the tick that
	# actually lands was silently dropped before FallingMove's fix added a
	# catch-up update() call after move_and_slide().
	#
	# Deliberately NOT compared against the raw teleport height: FallTracker
	# only starts counting once vertical speed crosses enter_to_falling_z_speed
	# (-2.0 m/s), a real, documented "grace period" (see
	# test_a_gentle_step_off_does_not_start_counting in test_fall_tracker.gd)
	# that eats several tenths of a metre of a from-rest drop before arming --
	# comparing against the raw drop height would fail even on CORRECT code.
	#
	# Instead this reconstructs, from directly observed positions, exactly
	# how far the player actually descended during the landing tick itself,
	# and checks the counter's final reading grew by exactly that much: once
	# armed and purely falling, fall_height == apex_y - world_y, so its
	# increase across any one tick must equal that tick's own drop in
	# world_y -- the one relationship the missing catch-up call broke.
	var world := TestWorld.build(tree, MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await _settle(world)

	var player: Player = world["player"]
	player.global_position.y += 6.0
	player.velocity = Vector3.ZERO

	# apex_y is reconstructed, not assumed: fall_tracker.fall_height read AFTER
	# a tick was computed by that tick's update() call using the position from
	# BEFORE that same tick (Player._physics_process() samples the tracker
	# ahead of MoveManager). So "fall_height read after step N" pairs
	# correctly with "position read before step N" -- pairing it with the
	# position read AFTER step N (one tick later) silently reintroduces the
	# very one-tick lag this test exists to catch, producing a false mismatch
	# on entirely correct code.
	var apex_y := 0.0
	var landed := false
	for i in 200:
		var y_pre: float = player.global_position.y
		await step(1)
		if player.move_manager.current_name == Move.WALKING and i > 1:
			landed = true
			break
		var fh_now: float = player.fall_tracker.fall_height
		if fh_now > 0.0:
			apex_y = fh_now + y_pre
	check(landed, "never landed after the drop")
	check_greater(apex_y, 0.0, "the fall tracker never armed during the drop -- test setup is wrong")

	# The counter's final reading must match apex_y minus the FRESH landed
	# position -- the whole point of the fix. Before it, the landing tick's
	# own descent (~0.16 m at this fall's ~9.7 m/s impact speed) was missing,
	# which the 0.001 m tolerance here would have caught easily.
	var expected: float = apex_y - player.global_position.y
	check_approx(player.last_landing_fall_height, expected, 0.001, \
		"the counter does not match the reconstructed ground truth -- got %f, expected %f" \
			% [player.last_landing_fall_height, expected])

	TestWorld.teardown(world)
	await step(1)
