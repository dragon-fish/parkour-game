extends TestCase

func _running_world(cfg: MovementConfig) -> Dictionary:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	return world

func test_crouching_at_speed_enters_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", \
		"pressing crouch while running should enter Slide, got %s" % player.state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_slide_gives_a_one_time_speed_boost() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var before := player.horizontal_speed()
	world["input"].press_crouch()
	await step(2)
	var just_after_entry := player.horizontal_speed()
	check_greater(just_after_entry, before, "entering a slide must add speed")

	# A per-tick boost would keep adding speed for as long as the slide lasts.
	# The boost is one-time, so speed from here on can only ever decay under
	# slide_friction — sampling later in the same slide must show a DROP, not
	# more growth.
	await step(20)
	check(player.state_machine.current_name == &"Slide", \
		"precondition: should still be sliding for the decay check to mean anything")
	var later := player.horizontal_speed()
	check(later < just_after_entry, \
		"speed grew further into the slide (%f -> %f); the boost must be one-time, not per-tick" \
		% [just_after_entry, later])
	TestWorld.teardown(world)
	await step(1)

func test_crouching_from_a_standstill_does_not_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"a standing crouch must not start a slide")
	TestWorld.teardown(world)
	await step(1)

func test_slide_decays_and_returns_to_ground() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Hold crouch and let friction do its work.
	for i in 600:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", \
		"a slide must eventually decay back to Ground")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_crouch_ends_the_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	world["input"].release_crouch()
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"releasing crouch should end the slide")
	TestWorld.teardown(world)
	await step(1)

func test_holding_crouch_does_not_strobe_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_crouch()

	# A held key produces exactly one press edge. If Slide entry keyed off
	# crouch_held instead of that edge, every Slide->Ground decay while the
	# key is still down would immediately re-cross slide_entry_speed and
	# re-enter Slide, strobing for as long as the key is held.
	var slide_entries := 0
	var was_sliding := false
	for i in 150:
		await step(1)
		var sliding: bool = player.state_machine.current_name == &"Slide"
		if sliding and not was_sliding:
			slide_entries += 1
		was_sliding = sliding

	check(slide_entries <= 1, \
		"holding crouch while running must not strobe in and out of Slide (entered %d times)" \
		% slide_entries)
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_is_shorter_while_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing := shape.height
	world["input"].press_crouch()
	await step(2)
	check_greater(standing, shape.height, "the capsule must shrink while sliding")

	world["input"].release_crouch()
	await step(10)
	check_approx(shape.height, standing, 0.001, "the capsule must return to standing height")
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_bottom_does_not_move_when_shrinking() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var shape := shape_node.shape as CapsuleShape3D

	var bottom_before := shape_node.position.y - shape.height * 0.5
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", \
		"precondition: should be sliding, or this check passes vacuously")
	var bottom_after := shape_node.position.y - shape.height * 0.5
	check_approx(bottom_after, bottom_before, 0.001, \
		"shrinking the capsule must keep its bottom in place, or footing shifts")
	TestWorld.teardown(world)
	await step(1)

func test_sliding_off_an_edge_enters_air() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Remove the floor from under the slide.
	world["floor"].global_position = Vector3(0.0, -80.0, 0.0)
	await step(5)
	check(player.state_machine.current_name == &"Air", \
		"leaving the ground mid-slide must enter Air")
	TestWorld.teardown(world)
	await step(1)
