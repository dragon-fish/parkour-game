extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

# 03 §3.3's confirmed multiplier chain. All eight scales are confirmed
# values; base_friction is the one number with no counterpart in the original
# and is expected to move during playtest, so every assertion here is stated
# as a RELATION between outputs rather than as an absolute.

func test_flat_ground_applies_only_the_braking_strength() -> void:
	var pawn := PawnConfig.new()
	var flat := Friction.walk_friction(pawn, 1.0, 0.0)
	assert_almost_eq(flat, pawn.base_friction * pawn.braking_friction_strength, 0.0001, \
		"flat friction is not base * braking strength")

func test_walking_uphill_costs_more_than_downhill() -> void:
	var pawn := PawnConfig.new()
	assert_gt(Friction.walk_friction(pawn, 1.0, -1.0), Friction.walk_friction(pawn, 1.0, 1.0), \
		"uphill walking is not more expensive than downhill")

func test_sliding_is_far_more_slope_sensitive_than_walking() -> void:
	# The whole reason the original feels the way it does on a ramp: walking's
	# spread is 1.1 vs 0.8, sliding's is 5.0 vs 1.8.
	var pawn := PawnConfig.new()
	var walk_spread := Friction.walk_friction(pawn, 1.0, -1.0) / Friction.walk_friction(pawn, 1.0, 1.0)
	var slide_spread := Friction.slide_friction(pawn, 1.0, -1.0) / Friction.slide_friction(pawn, 1.0, 1.0)
	assert_gt(slide_spread, walk_spread * 2.0, "sliding is not markedly more slope-sensitive")

func test_a_moves_own_modifier_scales_the_result() -> void:
	var pawn := PawnConfig.new()
	var full := Friction.slide_friction(pawn, 1.0, 0.0)
	var tenth := Friction.slide_friction(pawn, 0.1, 0.0)
	assert_almost_eq(tenth, full * 0.1, 0.0001, "the move's friction_modifier did not scale the result")

func test_the_walk_clamp_bounds_the_slope_term_only() -> void:
	# MinWalkFrictionModify / MaxWalkFrictionModify are named for walking, and
	# sliding's own 5.0 scale sits above the 2.0 ceiling -- so the clamp must
	# not be applied to sliding or the steepest slide case would be silently
	# capped at less than half its intended friction.
	var pawn := PawnConfig.new()
	pawn.upward_walk_friction_scale = 99.0
	var clamped := Friction.walk_friction(pawn, 1.0, -1.0)
	assert_almost_eq(clamped, pawn.base_friction * pawn.max_walk_friction_modify \
		* pawn.braking_friction_strength, 0.0001, "the walk clamp did not bind")
	pawn.upward_slide_friction_scale = 5.0
	var slide_up := Friction.slide_friction(pawn, 1.0, -1.0)
	assert_gt(slide_up, pawn.base_friction * pawn.max_walk_friction_modify, \
		"the walk clamp wrongly bound a slide")

func test_friction_is_never_negative() -> void:
	var pawn := PawnConfig.new()
	pawn.downward_slide_friction_scale = -3.0
	assert_gt(Friction.slide_friction(pawn, 1.0, 1.0) + 0.0001, 0.0, "friction went negative")

func test_flat_ground_grade_is_zero() -> void:
	# End-to-end regression test for Player.ground_grade(), the wiring that
	# turns real floor geometry into the `grade` the tests above only ever
	# receive as a literal argument. The brief's own rejected formula --
	# `-get_floor_normal().y` alone, with no projection of a direction onto
	# the floor -- is direction-independent and evaluates to -1 on a
	# perfectly flat floor (normal (0,1,0)), which after Friction's own
	# clampf(grade, -1, 1) reads as "straight uphill", permanently, even
	# standing still on level ground. None of the tests above could ever have
	# caught that: they never touch real floor geometry, only Friction's pure
	# functions. See Player.ground_grade()'s own comment for the fix.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)

	var player: Player = world["player"]
	assert_true(player.grounded, "player did not settle onto the floor -- test setup is wrong")

	var grade := player.ground_grade(Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(grade, 0.0, 0.0001, "flat ground did not read as grade 0")

	TestWorld.teardown(world)
	await step(1)
