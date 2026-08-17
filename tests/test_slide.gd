class_name TestSlide
extends TestCase

func _world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func _run_up(world: Dictionary, ticks: int) -> void:
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in ticks:
		await step(1)

func test_entering_a_slide_never_adds_speed() -> void:
	# The single behavioural difference from this project's old slide, and the
	# one that changes what the whole level teaches: the original has no
	# acceleration term anywhere in TdMove_Slide.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	var before: float = world["player"].horizontal_speed()
	world["input"].press_crouch()
	await step(1)
	await step(1)
	check(world["player"].horizontal_speed() <= before + 0.001, \
		"the slide added speed (%f -> %f)" % [before, world["player"].horizontal_speed()])
	TestWorld.teardown(world)
	await step(1)

func test_chaining_slides_cannot_ratchet_speed_upward() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	var peak: float = world["player"].horizontal_speed()
	for cycle in 6:
		world["input"].press_crouch()
		# Sample right after entry, before the rest of the press phase and the
		# release -- a boost applied only on entry (the bug this test exists to
		# catch) shows up HERE and decays away well before the end-of-cycle
		# sample below could ever see it. Confirmed by fault injection: without
		# this early sample, reinstating the old entry boost tripped
		# test_entering_a_slide_never_adds_speed but left this test green.
		await step(1)
		await step(1)
		peak = maxf(peak, world["player"].horizontal_speed())
		for i in 18:
			await step(1)
		world["input"].release_crouch()
		for i in 20:
			await step(1)
		peak = maxf(peak, world["player"].horizontal_speed())
	check(peak <= world["player"].config.pawn.ground_speed + 0.01, \
		"chained slides climbed past the ground ceiling (%f)" % peak)
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_ends_once_speed_decays_to_the_abort_speed() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	world["input"].press_crouch()
	await step(1)
	world["input"].state.move = Vector2.ZERO
	for i in 240:
		await step(1)
	check(world["player"].move_manager.current_name != Move.SLIDE, \
		"the slide never ended")
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_cannot_outlast_the_abort_time() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	world["input"].press_crouch()
	await step(1)
	# SlideAbortTime = 2.0 s. Give it a generous margin and it must be gone.
	for i in 150:
		await step(1)
	check(world["player"].move_manager.current_name != Move.SLIDE, \
		"the slide outlasted SlideAbortTime")
	TestWorld.teardown(world)
	await step(1)

func test_the_slide_declares_the_confirmed_friction_multiplier() -> void:
	var config := MovementConfig.new()
	check_approx(config.slide.friction_modifier, 0.1, 0.0001, \
		"slide friction_modifier is not the confirmed 0.1")

func test_uphill_slides_decay_harder_than_downhill_through_slide_move() -> void:
	# Grade sensitivity is reachable through the LIVE SlideMove path, not only
	# through Friction's pure functions (see test_friction.gd's
	# test_sliding_is_far_more_slope_sensitive_than_walking, which only ever
	# calls Friction.slide_friction() directly with literal grade arguments).
	# A real player, sliding on a real tilted floor, must lose speed
	# noticeably faster uphill than downhill -- "lose" for downhill only in
	# the RELATIVE sense this test checks; at this incline (30 degrees, past
	# the ~18.2 degree break-even -- see
	# test_downhill_past_break_even_grade_nets_acceleration_through_slide_move's
	# own comment) downhill actually GAINS speed, which only makes uphill's
	# own loss look larger by comparison.
	#
	# RUN_TICKS is generous (matching this file's other tests' own margin,
	# not the tighter 40 an earlier version of this test used) so entry speed
	# sits well above slide_abort_speed with room to spare: uphill's own
	# friction+gravity deceleration is severe enough now (grade -0.5 here) to
	# abort a slide entered too slowly within just a few ticks, which would
	# make the SLIDE-still-current check below fail for an unrelated reason.
	const INCLINE := deg_to_rad(30.0)
	const SETTLE_TICKS := 60
	const RUN_TICKS := 200
	const SLIDE_TICKS := 10

	var losses := {}
	for uphill in [true, false]:
		var world := TestWorld.build_on_slope(tree, MovementConfig.new(), INCLINE)
		await step(1)
		await step(SETTLE_TICKS)
		check(world["player"].grounded, "player did not settle onto the slope -- test setup is wrong")

		# Forward (local -Z) climbs this positively-inclined slope; backward
		# descends it -- see build_on_slope()'s own comment.
		world["input"].state.move = Vector2(0.0, 1.0 if uphill else -1.0)
		for i in RUN_TICKS:
			await step(1)
		var before: float = world["player"].horizontal_speed()

		world["input"].press_crouch()
		await step(1)
		for i in SLIDE_TICKS:
			await step(1)
		check(world["player"].move_manager.current_name == Move.SLIDE, \
			"never entered Slide -- test setup is wrong (uphill=%s)" % uphill)

		losses[uphill] = before - world["player"].horizontal_speed()
		TestWorld.teardown(world)
		await step(1)

	check(losses[true] > losses[false] * 1.5, \
		"an uphill slide did not decay markedly harder than a downhill one (uphill lost %f, downhill lost %f)" \
			% [losses[true], losses[false]])

## Break-even grade at this project's shipped constants (gravity 8.0,
## base_friction 40.0, friction_modifier 0.1, braking_friction_strength 0.5,
## downward_slide_friction_scale 1.8): solving gravity*g == decel(g) for
## g >= 0 gives g = (base_friction*friction_modifier*braking_friction_strength)
## / (gravity - base_friction*friction_modifier*braking_friction_strength*(downward_slide_friction_scale-1))
## = 2.0 / (8.0 - 2.0*0.8) = 2.0 / 6.4 = 0.3125, i.e. asin(0.3125) ~= 18.21
## degrees. Independently recomputed and confirmed against the running code
## via a standalone script before this constant was trusted -- see this
## file's own task report.
const BREAK_EVEN_GRADE := 0.3125

func test_downhill_past_break_even_grade_nets_acceleration_through_slide_move() -> void:
	# The property the model was missing entirely before this fix: gravity's
	# along-slope component (ordinary physics, NOT the deleted
	# slide_slope_accel bonus -- see _slide()'s own comment) must feed the
	# slide's scalar speed. Below is not enough to prove the term is wired
	# sign-correctly -- "decays more slowly downhill" could also be produced
	# by, say, a friction bug that merely UNDER-charges downhill. Only an
	# incline steep enough to flip the sign into genuine acceleration proves
	# it. 30 degrees gives grade 0.5, comfortably past the ~0.3125 break-even
	# above (net accel ~= +1.2 m/s^2 at this project's shipped constants).
	const INCLINE := deg_to_rad(30.0)
	const SETTLE_TICKS := 60
	const RUN_TICKS := 200
	const SLIDE_TICKS := 20

	check_greater(sin(INCLINE), BREAK_EVEN_GRADE, \
		"test setup is wrong -- INCLINE must sit past the break-even grade")

	var world := TestWorld.build_on_slope(tree, MovementConfig.new(), INCLINE)
	await step(1)
	await step(SETTLE_TICKS)
	check(world["player"].grounded, "player did not settle onto the slope -- test setup is wrong")

	# Backward (local +Z) descends this positively-inclined slope -- see
	# build_on_slope()'s own comment.
	world["input"].state.move = Vector2(0.0, -1.0)
	for i in RUN_TICKS:
		await step(1)
	var before: float = world["player"].horizontal_speed()

	world["input"].press_crouch()
	await step(1)
	for i in SLIDE_TICKS:
		await step(1)
	check(world["player"].move_manager.current_name == Move.SLIDE, \
		"never entered Slide -- test setup is wrong")

	check_greater(world["player"].horizontal_speed(), before, \
		"a downhill slide past the break-even grade did not net-accelerate (%f -> %f)" \
			% [before, world["player"].horizontal_speed()])
	TestWorld.teardown(world)
	await step(1)
