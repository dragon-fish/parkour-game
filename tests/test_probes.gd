extends TestCase

# The probes are the foundation both P2 states stand on, so they are tested
# against real geometry rather than mocked.

func _world_with_obstacle(height: float, distance: float, depth: float = 2.0) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, height, depth)
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

func test_an_obstacle_between_ledge_reach_and_vault_reach_is_vaultable() -> void:
	await step(1)
	# Thin obstacle (0.3 m deep, not the usual 2.0 m) whose entire footprint
	# sits beyond ledge_reach (1.0 m default) but within vault_reach (1.4 m
	# default): near face at 1.15 m, far face at 1.45 m. VaultLow/VaultHigh
	# each already use the correct reach and see it fine; this specifically
	# exercises SurfaceDown, which used to be pinned to ledge_reach for BOTH
	# queries and so looked straight past this obstacle's footprint to the
	# bare floor beyond it, reporting no vault even though the obstacle is a
	# textbook waist-high box.
	var world := await _world_with_obstacle(1.0, 1.3, 0.3)
	var player: Player = world["player"]
	check(player.probes.vault_query()["valid"], \
		"an obstacle beyond ledge_reach but within vault_reach must still be vaultable")
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

func test_dropping_the_foot_offset_changes_vault_validity() -> void:
	await step(1)
	# A LOW obstacle (0.5 m -- comfortably vaultable, comfortably clear of
	# both MIN_HEIGHT_EPSILON and vault_max_height) is the discriminator here:
	# world-space "top"/"edge" points never depend on foot_offset at all
	# (Probes.setup(cfg, 0.0) leaves them untouched), so a test that only
	# checks those -- as every other test in this file does -- would stay
	# green even if the feet-vs-origin conversion were silently dropped. Only
	# the valid/invalid GATE depends on it, and only for a height picked so
	# that subtracting the real foot offset (0.9 m) crosses the gate: with the
	# real offset the obstacle reads as ~0.5 m (valid); with a dropped offset
	# it reads as ~0.5 - 0.9 = -0.4 m (invalid).
	var world := await _world_with_obstacle(0.5, 1.2)
	var player: Player = world["player"]
	check(player.probes.vault_query()["valid"], \
		"a 0.5 m obstacle must be vaultable with the real foot offset applied")

	player.probes.setup(player.config, 0.0)
	check(not player.probes.vault_query()["valid"], \
		"dropping the foot offset must change whether this obstacle reads as vaultable -- " + \
		"pins Probes._feet_y()'s feet-vs-origin conversion")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)
