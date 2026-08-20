extends ParkourTest

# The probes are the foundation both P2 states stand on, so they are tested
# against real geometry rather than mocked.

func _world_with_obstacle(height: float, distance: float, depth: float = 2.0) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

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
	get_tree().root.add_child(obstacle)
	await step(3)
	world["obstacle"] = obstacle
	return world

func test_a_waist_high_obstacle_is_vaultable() -> void:
	await step(1)
	var world := await _world_with_obstacle(1.0, 1.2)
	var player: Player = world["player"]
	var query: Dictionary = player.probes.vault_query()
	assert_true(query["valid"], "a 1.0 m obstacle at 1.2 m should be vaultable")
	assert_almost_eq(query["top"].y, 1.0, 0.15, "the reported top surface should match the obstacle")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_tall_wall_is_not_vaultable() -> void:
	await step(1)
	var world := await _world_with_obstacle(3.0, 1.2)
	var player: Player = world["player"]
	assert_true(not player.probes.vault_query()["valid"], \
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
	assert_true(player.probes.vault_query()["valid"], \
		"an obstacle beyond ledge_reach but within vault_reach must still be vaultable")
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_nothing_ahead_is_not_vaultable() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	assert_true(not player.probes.vault_query()["valid"], "empty space must not report as vaultable")
	TestWorld.teardown(world)
	await step(1)

func test_a_reachable_ledge_is_detected() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

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
	get_tree().root.add_child(block)
	await step(3)

	var player: Player = world["player"]
	var query: Dictionary = player.probes.ledge_query()
	assert_true(query["valid"], "a ledge at head height should be detected")
	assert_almost_eq(query["edge"].y, 2.6, 0.15, "the reported edge height should match the block top")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_ledge_far_above_reach_is_not_detected() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

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
	get_tree().root.add_child(block)
	await step(3)

	var player: Player = world["player"]
	assert_true(not player.probes.ledge_query()["valid"], \
		"an 8 m wall offers no reachable ledge")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_misreporting_the_foot_offset_changes_vault_validity() -> void:
	await step(1)
	# World-space "top"/"edge" points never depend on foot_offset, so a test
	# that only checks those -- as every other test in this file does -- would
	# stay green even if the feet-vs-origin conversion were silently dropped.
	# Only the valid/invalid GATE depends on it, so this feeds Probes a WRONG
	# offset and requires the verdict on unchanged geometry to flip.
	#
	# The wrong offset is deliberately an INFLATED one (1.6 m rather than 0.0),
	# and the discriminating bound is vault_max_height rather than
	# MIN_HEIGHT_EPSILON. Since Probes derives SurfaceDown's whole vertical
	# placement from foot_offset (it must start above the tallest reachable top
	# and reach just below the feet), a zeroed offset also pulls the ray's
	# bottom end up to just under the body ORIGIN -- so a low obstacle would be
	# rejected because the ray no longer reaches it, not because the height
	# gate rejected its height, and the test would pass for the wrong reason.
	# An inflated offset moves the ray's bottom end DOWN instead: the obstacle
	# is comfortably in view either way, and only the arithmetic changes.
	# 1.0 m obstacle, real offset 0.9: reads ~1.0 m, inside vault_max_height
	# (1.3). Same obstacle, offset 1.6: reads ~1.7 m, over the limit.
	var world := await _world_with_obstacle(1.0, 1.2)
	var player: Player = world["player"]
	assert_true(player.probes.vault_query()["valid"], \
		"a 1.0 m obstacle must be vaultable with the real foot offset applied")

	player.probes.setup(player.config, 1.6)
	assert_true(not player.probes.vault_query()["valid"], \
		"misreporting the foot offset must change whether this obstacle reads as vaultable -- " + \
		"pins Probes._feet_y()'s feet-vs-origin conversion")

	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## Companion to the above, on the other thing foot_offset governs since
## SurfaceDown's placement became derived: the ray must actually SEE a surface
## at the configured maximum. The panel generates each slider's range as three
## times the default, so a human can drive ledge_max_height to 8.4 m -- and with
## the ray's origin baked at a fixed height the knob would silently stop working
## somewhere around 3.1 m, with tall ledges reading as "no ledge" rather than as
## "too high". Raising the configured maximum must raise the ray with it.
func test_raising_the_configured_ledge_maximum_raises_what_the_probe_can_see() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

	# A block whose top is well above the DEFAULT ledge_max_height (2.8) but
	# still a plausible ledge once the maximum is raised.
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.2, 2.0)
	shape.shape = box
	block.add_child(shape)
	block.position = Vector3(0.0, 2.1, -1.1)
	get_tree().root.add_child(block)
	await step(3)

	var player: Player = world["player"]
	assert_true(not player.probes.ledge_query()["valid"], \
		"precondition: a 4.2 m top is out of reach at the default ledge_max_height")

	# The panel writes straight into the shared config object at runtime, with
	# no call back into Probes — so this is exactly how a slider drag reaches
	# the rays.
	cfg.ledge_max_height = 4.5
	var query: Dictionary = player.probes.ledge_query()
	assert_true(query["valid"], \
		"raising ledge_max_height did not bring the 4.2 m top into view -- the probe's reach is not following the live config")
	# The DECISIVE assertion, and not a redundant one: with the ray's origin
	# left baked at its old fixed height it sits INSIDE this block, and
	# hit_from_inside makes it report its own origin as the hit. That is a
	# phantom ledge a metre below the real top -- "valid" above still passes,
	# at a height the player would grab at and a surface that is not there.
	# Measured with the derivation reverted: edge.y comes back as 3.10 rather
	# than 4.20. Checking only validity would miss it entirely.
	assert_almost_eq(query["edge"].y, 4.2, 0.15, \
		"the probe reported an edge at the wrong height -- with a fixed ray origin buried inside the block, hit_from_inside reports the ray's own origin as a phantom ledge")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

## The other half of IMPORTANT 4: VaultHigh is shared by both queries, and it
## used to be pinned once at max(vault_reach, ledge_reach). That handed the
## LEDGE configuration a veto over the VAULT's chest-clearance test — push
## ledge_reach past vault_reach and VaultHigh starts finding obstacles that are
## none of vault_query()'s business, each of which reads as "this is a wall"
## and suppresses the vault outright.
func test_the_ledge_reach_does_not_govern_the_vaults_chest_test() -> void:
	await step(1)
	# A perfectly ordinary waist-high box, 1.2 m ahead: vaultable by every
	# measure vault_query() is entitled to apply.
	var world := await _world_with_obstacle(1.0, 1.2)
	var player: Player = world["player"]
	assert_true(player.probes.vault_query()["valid"], "precondition: this obstacle should be vaultable")

	# Now put a WALL beyond it, past vault_reach but within a raised
	# ledge_reach. Nothing about the vault has changed.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 2.0, -2.2)
	get_tree().root.add_child(wall)
	await step(3)

	assert_true(player.probes.vault_query()["valid"], \
		"precondition: a wall beyond vault_reach must not affect the vault verdict")

	player.config.ledge_reach = 2.6
	assert_true(player.probes.vault_query()["valid"], \
		"raising ledge_reach suppressed a vault it has nothing to do with -- the chest-clearance ray must be asked at vault_reach, not at whichever reach is larger")

	wall.queue_free()
	world["obstacle"].queue_free()
	TestWorld.teardown(world)
	await step(1)
