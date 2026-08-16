extends TestCase

# CrouchState is reached today only from a Slide that decayed or timed out
# while the key was still held (see tests/test_slide_state.gd for that
# hand-off). These tests drive the state directly via state_machine.start(),
# the same pattern test_wall_run.gd and others already use, so they exercise
# CrouchState's own behaviour without re-deriving a slide every time.

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world

## Parks a slab just above the crouched capsule, across the player's path, so
## has_headroom() (sized for the STANDING capsule) is false. Mirrors
## tests/test_slide_state.gd's own _add_ceiling_over.
func _add_ceiling_over(player: Player) -> StaticBody3D:
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.5, 80.0)
	shape.shape = box
	ceiling.add_child(shape)
	ceiling.position = player.global_position + Vector3(0.0, 0.45, 0.0)
	tree.root.add_child(ceiling)
	return ceiling

func test_crouched_movement_is_slower_than_running() -> void:
	var run_world := await _spawn()
	var run_player: Player = run_world["player"]
	var run_input: ScriptedInputSource = run_world["input"]
	run_input.state.move = Vector2(0.0, 1.0)
	await step(60)
	var run_speed := run_player.horizontal_speed()
	TestWorld.teardown(run_world)
	await step(1)

	var crouch_world := await _spawn()
	var crouch_player: Player = crouch_world["player"]
	var crouch_input: ScriptedInputSource = crouch_world["input"]
	crouch_player.state_machine.start(PlayerState.CROUCH)
	crouch_input.state.move = Vector2(0.0, 1.0)
	crouch_input.state.crouch_held = true
	await step(60)
	var crouch_speed := crouch_player.horizontal_speed()
	var cfg: MovementConfig = crouch_player.config

	check_greater(run_speed, crouch_speed, \
		"crouched movement (%f) was not slower than running (%f)" % [crouch_speed, run_speed])
	check_approx(crouch_speed, cfg.ground_speed * cfg.crouch_speed_pct, 0.1, \
		"crouched top speed did not match ground_speed * crouch_speed_pct (got %f, expected %f)" \
			% [crouch_speed, cfg.ground_speed * cfg.crouch_speed_pct])
	TestWorld.teardown(crouch_world)
	await step(1)

func test_the_capsule_is_the_crouched_height_while_crouching() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var cfg: MovementConfig = player.config
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing := shape.height

	# Held, or CrouchState stands the player back up on its very first tick
	# (has_headroom() is true here, nothing overhead) and the capsule pops
	# straight back to standing before this ever gets to check anything.
	input.state.crouch_held = true
	player.state_machine.start(PlayerState.CROUCH)
	await step(2)
	check_approx(shape.height, cfg.crouch_capsule_height, 0.001, \
		"the capsule must be crouch_capsule_height while crouching")
	check_greater(standing, shape.height, "the capsule must be shorter than standing while crouching")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_crouch_under_a_low_ceiling_does_not_stand_up() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	player.state_machine.start(PlayerState.CROUCH)
	input.state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Crouch", "precondition: should be crouching")

	var ceiling := _add_ceiling_over(player)
	await step(1)

	input.state.crouch_held = false
	await step(10)
	check(player.state_machine.current_name == &"Crouch", \
		"releasing crouch under a ceiling must not stand the player up, got %s" \
			% player.state_machine.current_name)

	ceiling.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_standing_up_once_the_ceiling_is_gone() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	player.state_machine.start(PlayerState.CROUCH)
	input.state.crouch_held = true
	await step(2)

	var ceiling := _add_ceiling_over(player)
	await step(1)

	input.state.crouch_held = false
	await step(10)
	check(player.state_machine.current_name == &"Crouch", \
		"precondition: a ceiling should still be blocking standing up, got %s" \
			% player.state_machine.current_name)

	ceiling.queue_free()
	await step(20)
	check(player.state_machine.current_name == &"Ground", \
		"once the ceiling is gone the player should stand up, got %s" % player.state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

## Structural tripwire mirroring tests/test_slide_state.gd's own pair: of
## every state name PlayerState declares, crouch_state.gd may only ever
## mention Ground and Air. Referenced by name from slide_state.gd's own
## comment on the Slide -> Crouch hand-off, so if Crouch ever legitimately
## needs to reach anywhere else, both this and that comment need updating
## together, deliberately.
func test_crouch_can_only_reach_ground_and_air() -> void:
	await step(1)
	var source := FileAccess.get_file_as_string("res://scripts/player/states/crouch_state.gd")
	check(source.length() > 0, "could not read crouch_state.gd")

	var state_script: GDScript = load("res://scripts/player/states/player_state.gd")
	var referenced: Array[String] = []
	for key in state_script.get_script_constant_map().keys():
		var constant_name := String(key)
		if constant_name == "KEEP" or constant_name == "CROUCH":
			continue
		var pattern := RegEx.new()
		pattern.compile("\\b%s\\b" % constant_name)
		if pattern.search(source) != null:
			referenced.append(constant_name)
	referenced.sort()
	var expected: Array[String] = ["AIR", "GROUND"]
	check(referenced == expected, \
		"Crouch must be able to reach exactly Ground and Air, but crouch_state.gd references %s" \
		% str(referenced))
