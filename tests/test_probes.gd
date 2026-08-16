extends TestCase

# The probes are the foundation both P2 states stand on, so they are tested
# against real geometry rather than mocked.

func _world_with_obstacle(height: float, distance: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, height, 2.0)
	shape.shape = box
	obstacle.add_child(shape)
	# Position set BEFORE add_child(): a body added to the tree first sits at
	# the world origin for a frame, overlapping the player standing there and
	# getting physically launched by depenetration -- a failure unrelated to
	# what this test checks. Confirmed by direct measurement: the add-then-move
	# ordering here sent the player's body origin from y=0.90 to y=2.15 on the
	# very next physics step, purely from the box's transient origin overlap.
	# Player faces -Z by default; put the obstacle in front of it.
	obstacle.position = Vector3(0.0, height * 0.5, -distance)
	tree.root.add_child(obstacle)
	await step(3)
	world["obstacle"] = obstacle
	return world

func test_a_waist_high_obstacle_is_vaultable() -> void:
	await step(1)
	var world := await _world_with_obstacle(1.0, 1.2)
	var player: Player = world["player"]
	var query: Dictionary = player.probes.vault_query()
	check(query["valid"], "a 1.0 m obstacle at 1.2 m should be vaultable")
	check_approx(query["top"].y, 1.0, 0.15, "the reported top surface should match the obstacle")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_tall_wall_is_not_vaultable() -> void:
	await step(1)
	var world := await _world_with_obstacle(3.0, 1.2)
	var player: Player = world["player"]
	check(not player.probes.vault_query()["valid"], \
		"a 3 m wall must not report as vaultable")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_nothing_ahead_is_not_vaultable() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	check(not player.probes.vault_query()["valid"], "empty space must not report as vaultable")
	TestWorld.teardown(world)
	await step(1)

func test_a_reachable_ledge_is_detected() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	# A tall block whose top is just above the player's head.
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 2.6, 2.0)
	shape.shape = box
	block.add_child(shape)
	# Position set BEFORE add_child() -- see the comment in
	# _world_with_obstacle() for why the add-then-move ordering launches the
	# player.
	block.position = Vector3(0.0, 1.3, -1.1)
	tree.root.add_child(block)
	await step(3)

	var player: Player = world["player"]
	var query: Dictionary = player.probes.ledge_query()
	check(query["valid"], "a ledge at head height should be detected")
	check_approx(query["edge"].y, 2.6, 0.15, "the reported edge height should match the block top")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_ledge_far_above_reach_is_not_detected() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 8.0, 2.0)
	shape.shape = box
	block.add_child(shape)
	# Position set BEFORE add_child() -- see the comment in
	# _world_with_obstacle() for why the add-then-move ordering launches the
	# player.
	block.position = Vector3(0.0, 4.0, -1.1)
	tree.root.add_child(block)
	await step(3)

	var player: Player = world["player"]
	check(not player.probes.ledge_query()["valid"], \
		"an 8 m wall offers no reachable ledge")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)
