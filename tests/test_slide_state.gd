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
	world["input"].state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Slide", \
		"crouching while running should enter Slide, got %s" % player.state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_slide_gives_a_one_time_speed_boost() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var before := player.horizontal_speed()
	world["input"].state.crouch_held = true
	await step(2)
	check_greater(player.horizontal_speed(), before, "entering a slide must add speed")
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
	world["input"].state.crouch_held = true
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
	world["input"].state.crouch_held = true
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
	world["input"].state.crouch_held = true
	await step(2)
	world["input"].state.crouch_held = false
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"releasing crouch should end the slide")
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_is_shorter_while_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing := shape.height
	world["input"].state.crouch_held = true
	await step(2)
	check_greater(standing, shape.height, "the capsule must shrink while sliding")

	world["input"].state.crouch_held = false
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
	world["input"].state.crouch_held = true
	await step(2)
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
	world["input"].state.crouch_held = true
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Remove the floor from under the slide.
	world["floor"].global_position = Vector3(0.0, -80.0, 0.0)
	await step(5)
	check(player.state_machine.current_name == &"Air", \
		"leaving the ground mid-slide must enter Air")
	TestWorld.teardown(world)
	await step(1)
