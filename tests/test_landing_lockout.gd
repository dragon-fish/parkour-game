extends ParkourTest

# [ME:CONFIRMED spec §时间轴] 2.00 s is measured, not designed: six hard
# landings in the original, timed from the last Falling frame to the first
# Walking frame, read 2.03 / 2.00 / 2.00 / 2.00 / 2.00 / 2.02.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_lockout_is_the_measured_two_seconds() -> void:
	var cfg := MovementConfig.new()
	assert_almost_eq(cfg.landing.lockout_time, 2.0, 0.0001, \
		"the hard-landing lockout is not the measured 2.00 s")

func test_a_hard_unrolled_landing_enters_landing() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	# Above hard_landing_height, below the death threshold, no roll input.
	player.global_position.y += cfg.pawn.hard_landing_height + 1.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	assert_true(player.move_manager.current_name == Move.LANDING, \
		"a hard unrolled landing did not enter Landing")
	TestWorld.teardown(world)
	await step(1)

func test_a_soft_landing_skips_it_entirely() -> void:
	# Below hard_landing_height there is no penalty at all (03 §3.1), so there
	# must be no lockout either.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.hard_landing_height - 2.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.grounded and player.move_manager.current_name != Move.FALLING:
			break
	assert_true(player.move_manager.current_name != Move.LANDING, \
		"a landing below the hard threshold was locked out")
	TestWorld.teardown(world)
	await step(1)

func test_the_lockout_actually_pins_the_yaw() -> void:
	# B1 REGRESSION. LandingConfig declares a +-0.2 rad look fan, but left
	# absolute_yaw_constraint at its default false, and CameraRig.apply_look()
	# then measures `relative` against body.rotation.y -- the facing the player
	# has THIS tick. The clamp collapses into a per-tick RATE limit of ~0.2 rad
	# (about 688 deg/s), which no ordinary mouse sweep comes near, so the
	# lockout refused nothing at all and the view could spin freely through a
	# hard landing the body is supposedly pinned by.
	#
	# Verified to go red with absolute_yaw_constraint removed: the body turns
	# 0.2 rad EVERY tick instead, and the deviation below runs away immediately.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.hard_landing_height + 1.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	assert_true(player.move_manager.current_name == Move.LANDING, \
		"test setup is wrong: never entered Landing")

	# The reference facing is captured by CameraRig.set_look_constraint() on
	# the tick the constraint first becomes active, which MoveManager pushed at
	# the end of the very tick detected above -- so the body's yaw right now IS
	# that reference.
	var reference: float = player.rotation.y

	# ~0.22 rad of requested yaw per tick at the shipped mouse sensitivity:
	# comfortably above the 0.2 rad fan, and sustained, so a rate limit would
	# wave it through indefinitely while a fan cannot.
	var input: ScriptedInputSource = world["input"]
	input.state.look = Vector2(-100.0, 0.0)

	# Tracked as a running MAXIMUM rather than sampled once at the end: a yaw
	# that escapes the fan keeps accumulating and wraps, so a single late
	# sample could land back near the reference by coincidence.
	var worst: float = 0.0
	for i in 100:
		await step(1)
		worst = maxf(worst, absf(wrapf(player.rotation.y - reference, -PI, PI)))
	assert_true(player.move_manager.current_name == Move.LANDING, \
		"test setup is wrong: the lockout ended before the measurement did")
	assert_true(0.2 + 0.01 > worst, \
		"the landing lockout let the view turn %f rad past its own +-0.2 fan" % worst)

	input.state.look = Vector2.ZERO
	TestWorld.teardown(world)
	await step(1)

func test_the_sink_is_there_on_the_frame_the_landing_begins() -> void:
	# SAME CLASS AS THE ROLL'S ENTRY FLICKER. MoveManager calls enter() mid-tick
	# and does not run the move's own physics_update() on that tick, so the sink
	# and the downward pitch were first written a frame later -- while
	# Player.update_effects() deliberately skips writing the crouch for LANDING,
	# leaving the entry frame showing the airborne view.
	#
	# Milder than the roll's case: this is the effect arriving one frame late
	# rather than a flash to a wrong value. It is still the impact frame -- the
	# one frame of a hard landing anyone actually looks at.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.hard_landing_height + 1.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	assert_true(player.move_manager.current_name == Move.LANDING, \
		"a hard unrolled landing did not enter Landing")

	# update_effects() has already run by the end of this step, so the rig shows
	# whatever the entry frame settled on. The offset tips the view DOWN, and
	# the rig subtracts it: see CameraRig.set_landing_pitch_offset().
	assert_lt(player.camera_rig.rotation.x, -cfg.landing.camera_pitch_offset * 0.9, \
		"the impact frame showed a pitch of %.1f degrees, with the sink not yet applied" \
		% rad_to_deg(player.camera_rig.rotation.x))

	TestWorld.teardown(world)
	await step(1)
