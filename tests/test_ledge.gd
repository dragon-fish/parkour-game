extends TestCase

func _jump_at_ledge(block_height: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, block_height, 4.0)
	shape.shape = box
	block.add_child(shape)
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, block_height * 0.5, -6.0)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.sprint_held = true
	world["block"] = block
	return world

func test_reaching_a_ledge_grabs_it() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]

	var grabbed := false
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			grabbed = true
			break
	check(grabbed, "jumping at a head-height ledge should grab it")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_hanging_holds_position() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	check(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2.ZERO
	var held := player.global_position
	await step(20)
	check(player.global_position.distance_to(held) < 0.05, \
		"a hanging player must not drift or fall")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_pressing_forward_mantles_onto_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", "mantling should end on the ledge top")
	check_greater(player.global_position.y, 2.0, "the player should now be above the ledge")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_crouching_releases_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2.ZERO
	world["input"].state.crouch_held = true
	await step(5)
	check(player.state_machine.current_name == &"Air", "crouching should drop off the ledge")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)
