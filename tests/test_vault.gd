extends TestCase

func _running_at_obstacle(height: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, height, 1.0)
	shape.shape = box
	obstacle.add_child(shape)
	tree.root.add_child(obstacle)
	await step(1)
	obstacle.global_position = Vector3(0.0, height * 0.5, -8.0)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.sprint_held = true
	world["obstacle"] = obstacle
	return world

func test_running_into_a_low_obstacle_vaults_it() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]

	var vaulted := false
	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			vaulted = true
			break
	check(vaulted, "running into a waist-high obstacle should start a vault")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_ends_beyond_the_obstacle() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]
	var obstacle: StaticBody3D = world["obstacle"]

	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break

	check(player.global_position.z < obstacle.global_position.z, \
		"the vault should leave the player past the obstacle")

	obstacle.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_vault_keeps_most_of_the_approach_speed() -> void:
	await step(1)
	var world := await _running_at_obstacle(1.0)
	var player: Player = world["player"]

	var approach := 0.0
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Vault":
			break
		approach = player.horizontal_speed()
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Vault":
			break

	# Vaulting is a shortcut, not a speed bump — it must not cost more than a
	# plain landing would.
	check_greater(player.horizontal_speed(), approach * 0.5, \
		"vaulting bled too much speed (%f from %f)" % [player.horizontal_speed(), approach])

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_wall_is_not_vaulted() -> void:
	await step(1)
	var world := await _running_at_obstacle(3.0)
	var player: Player = world["player"]

	for i in 300:
		await step(1)
		check(player.state_machine.current_name != &"Vault", \
			"a 3 m wall must never be vaulted")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)
