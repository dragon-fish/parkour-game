extends TestCase

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world

func test_jump_leaves_the_ground() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	check(player.state_machine.current_name == &"Ground", "precondition: should start grounded")
	input.press_jump()
	await step(3)
	check(player.state_machine.current_name == &"Air", "jump did not enter Air")
	check_greater(player.velocity.y, 0.0, "jump did not produce upward velocity")

	TestWorld.teardown(world)
	await step(1)

func test_player_returns_to_ground_after_a_jump() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.press_jump()
	await step(3)
	input.release_jump()
	await step(180)

	check(player.state_machine.current_name == &"Ground", \
		"player never landed, state = %s" % player.state_machine.current_name)
	check_greater(player.last_landing_speed, 0.0, "landing speed was not recorded")

	TestWorld.teardown(world)
	await step(1)

func test_air_control_is_weaker_than_ground_control() -> void:
	var cfg := MovementConfig.new()

	# Ground run-up: how much speed is gained in 10 ticks from rest, grounded.
	var ground_world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(ground_world)
	await step(30)
	var ground_player: Player = ground_world["player"]
	ground_world["input"].state.move = Vector2(0.0, 1.0)
	await step(10)
	var ground_gain := ground_player.horizontal_speed()
	TestWorld.teardown(ground_world)
	await step(1)

	# Air run-up: same 10 ticks of forward input, but airborne from rest.
	var air_world := TestWorld.build(tree, cfg)
	await step(1)
	air_world["floor"].global_position = Vector3(0.0, -60.0, 0.0)
	air_world["player"].global_position = Vector3(0.0, 0.0, 0.0)
	await step(10)
	var air_player: Player = air_world["player"]
	air_world["input"].state.move = Vector2(0.0, 1.0)
	await step(10)
	var air_gain := air_player.horizontal_speed()
	TestWorld.teardown(air_world)
	await step(1)

	check_greater(ground_gain, air_gain, \
		"air control must be weaker than ground control (ground %f vs air %f)" % [ground_gain, air_gain])

## tools/probe_speed_exploit.gd measured chained jumps (no air-strafe) against
## the real Player and found them flat: 9.00 -> 9.00 every hop, +0.00. Cheap
## insurance against a future landing-cost or air-control change silently
## turning jump-chaining into the same kind of stacking exploit chained
## slides had. Compares an early hop's landing speed to a late one in the
## same run, so this holds under tuning -- growth ACROSS the chain is what a
## stacking exploit looks like, not any particular absolute speed.
func test_chained_jumps_do_not_stack_speed() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)

	var first_after := 0.0
	var last_after := 0.0
	for hop in 8:
		input.press_jump()
		await step(3)
		input.release_jump()
		var guard := 0
		while player.state_machine.current_name != &"Ground" and guard < 300:
			await step(1)
			guard += 1
		if hop == 0:
			first_after = player.horizontal_speed()
		last_after = player.horizontal_speed()

	check(last_after <= first_after + 0.1, \
		"chained jumps grew horizontal speed across the chain (hop 1 landed at %f, hop 8 at %f) -- jumping must not be a way to gain speed" \
		% [first_after, last_after])

	TestWorld.teardown(world)
	await step(1)

## Companion to test_chained_jumps_do_not_stack_speed, which only ever holds
## a fixed forward input. This drives an actual air-strafe pattern -- a
## rotating wish_dir every few ticks while airborne, the way a player trying
## to exploit air_accelerate()'s Quake-style projection would -- across a
## full chain of jumps, and pins the result against MovementConfig.sprint_speed
## itself (never a literal), per the guide's AirControl = 0.025 model: air
## control is not blocked by a low air_max_speed ceiling (see that field's own
## comment), so the only thing standing between this and a repeat of the old
## air_accel=12.0 / air_max_speed=9.0 ratchet (confirmed via
## tools/probe_speed_exploit.gd against the live states before this test was
## written: flat at sprint_speed across 8 chained hops, both with and without
## strafing) is air_accel being small enough that a full hangtime of
## continuous strafing cannot add meaningful speed. The 1.1x allowance is
## itself relative to sprint_speed, not a bare number, so a future retune of
## sprint_speed alone does not silently loosen this pin.
func test_air_strafing_across_chained_jumps_never_exceeds_the_ground_speed_cap() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var cfg: MovementConfig = player.config

	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)

	var cap: float = cfg.sprint_speed * 1.1
	var strafe_ticks := 0
	for hop in 8:
		input.press_jump()
		var guard := 0
		while player.state_machine.current_name != &"Ground" and guard < 300:
			# Rotating wish_dir: the closest this project's simple projection
			# model has to a strafe-jump's "keep wish_dir just ahead of
			# velocity" technique.
			var t := float(strafe_ticks) * 0.15
			input.state.move = Vector2(sin(t), 1.0).normalized()
			await step(1)
			strafe_ticks += 1
			guard += 1
		input.release_jump()
		input.state.move = Vector2(0.0, 1.0)
		check(player.horizontal_speed() <= cap, \
			"hop %d landed at %f m/s, above %f (sprint_speed %f x 1.1) -- air-strafing must not ratchet speed past the ground cap" \
			% [hop + 1, player.horizontal_speed(), cap, cfg.sprint_speed])
		await step(10)

	TestWorld.teardown(world)
	await step(1)

func test_coyote_time_allows_a_jump_just_after_leaving_ground() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Force the player off the floor without jumping, then jump within the
	# coyote window.
	player.global_position = Vector3(0.0, 3.0, 0.0)
	await step(2)
	check(player.state_machine.current_name == &"Air", "precondition: should be airborne")

	input.press_jump()
	await step(1)
	check_greater(player.velocity.y, 0.0, "coyote jump did not fire")

	TestWorld.teardown(world)
	await step(1)
