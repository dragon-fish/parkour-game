extends TestCase

# Landing is where the "speed is hard to earn, easy to lose" rule bites. These
# assert the ORDERING of outcomes, never the amounts, so tuning cannot break them.

func _airborne_world(cfg: MovementConfig, drop_height: float) -> Dictionary:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	world["floor"].global_position = Vector3(0.0, -0.5, 0.0)
	world["player"].global_position = Vector3(0.0, drop_height, 0.0)
	await step(30)
	return world

## Runs the player up to speed on the ground, then drops it from `height` with
## crouch either held (roll) or not, and returns the horizontal speed on landing.
func _speed_after_drop(height: float, crouch: bool) -> float:
	return await _speed_after_drop_with(MovementConfig.new(), height, crouch)

## Same, on a caller-supplied config, so a test can vary one parameter and
## compare the outcome against the default.
func _speed_after_drop_with(cfg: MovementConfig, height: float, crouch: bool) -> float:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	await step(90)

	# Lift the runner to the drop height without changing its horizontal motion.
	player.global_position = Vector3(player.global_position.x, height, player.global_position.z)
	await step(2)
	input.state.crouch_held = crouch

	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	var speed := player.horizontal_speed()
	TestWorld.teardown(world)
	await step(1)
	return speed

func test_a_plain_landing_costs_speed() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	await step(90)
	var running_speed := player.horizontal_speed()

	player.global_position = Vector3(player.global_position.x, 12.0, player.global_position.z)
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check_greater(running_speed, player.horizontal_speed(), \
		"a plain landing from height must cost horizontal speed")
	TestWorld.teardown(world)
	await step(1)

func test_rolling_keeps_more_speed_than_a_plain_landing() -> void:
	await step(1)
	var plain := await _speed_after_drop(12.0, false)
	var rolled := await _speed_after_drop(12.0, true)
	check_greater(rolled, plain, "rolling must preserve more speed than landing flat")

func test_a_higher_fall_costs_more_speed() -> void:
	await step(1)
	var shallow := await _speed_after_drop(4.0, false)
	var deep := await _speed_after_drop(16.0, false)
	check_greater(shallow, deep, "a deeper fall must cost more speed than a shallow one")

func test_the_camera_dip_reference_does_not_retune_the_landing_cost() -> void:
	await step(1)
	# A 4 m drop lands at roughly 8 m/s (v = sqrt(2 * gravity * height) at the
	# post-retune gravity of 8.0 m/s^2), which is BELOW land_cost_speed_ref's
	# default of 9.21 — so the severity curve is still on its ramp and a change
	# of reference actually moves the result. Dropping from high enough to
	# saturate the curve would make this test pass no matter what it read.
	var default_speed := await _speed_after_drop(4.0, false)

	# land_dip_speed_ref is a CAMERA parameter — how hard the view drops on
	# impact. Moving it must not change the physics. It used to double as the
	# momentum curve's reference, so dragging the camera slider silently
	# retuned how much speed a landing cost.
	var cfg := MovementConfig.new()
	cfg.land_dip_speed_ref = 6.0
	var tuned_speed := await _speed_after_drop_with(cfg, 4.0, false)
	check_approx(tuned_speed, default_speed, 0.01, \
		"tuning the camera's landing dip changed how much speed the landing cost")

func test_a_landing_can_never_add_speed_however_the_keep_ratio_is_tuned() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	# The tuning panel builds every slider's range as default * 3, so both keep
	# ratios are draggable well past 1.0. _apply_landing_cost's own comment
	# says a landing may only ever COST momentum; that has to hold at every
	# reachable slider position, not just the default one.
	cfg.roll_speed_keep = cfg.roll_speed_keep * 3.0
	cfg.land_speed_keep = cfg.land_speed_keep * 3.0
	check_greater(cfg.roll_speed_keep, 1.0, "precondition: the tuned keep ratio should exceed 1.0")

	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	await step(90)
	var running_speed := player.horizontal_speed()

	player.global_position = Vector3(player.global_position.x, 12.0, player.global_position.z)
	await step(2)
	input.state.crouch_held = true
	var landing_speed := running_speed
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			landing_speed = player.horizontal_speed()
			break
	check(landing_speed <= running_speed + 0.001, \
		"a landing added speed (%f -> %f); no slider position may break that invariant" \
		% [running_speed, landing_speed])
	TestWorld.teardown(world)
	await step(1)

## Both cases, because only asserting the positive one would let a hardcoded
## `rolled = true` pass: the flag has to distinguish the two landings, not just
## report the interesting one.
func test_the_roll_flag_reports_which_landing_happened() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _airborne_world(cfg, 12.0)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.last_landing_rolled, "a crouched landing from height should be flagged as a roll")
	TestWorld.teardown(world)
	await step(1)

	var plain_cfg := MovementConfig.new()
	var plain_world := await _airborne_world(plain_cfg, 12.0)
	var plain_player: Player = plain_world["player"]
	plain_world["input"].state.crouch_held = false
	for i in 400:
		await step(1)
		if plain_player.state_machine.current_name == &"Ground":
			break
	check(plain_player.state_machine.current_name == &"Ground", \
		"precondition: the uncrouched drop never landed")
	check(not plain_player.last_landing_rolled, \
		"an uncrouched landing from the same height must NOT be flagged as a roll")
	TestWorld.teardown(plain_world)
	await step(1)
