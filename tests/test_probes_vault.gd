extends ParkourTest

# Task 13: the two things the variant table needs that vault_query() could
# not answer before -- how far ahead the obstacle is, and whether anything is
# landable beyond its far side.
#
# Box placements and settle time below are pinned by debugging with print(),
# not guessed:
#
# 1. Box position: SurfaceDown's downward ray lands at a FIXED forward reach
#    (vault_reach, 1.4 m by default) regardless of the obstacle's own depth --
#    see _query_surface() in probes.gd. A box placed short of that point lets
#    the top-find ray sail past it onto open floor, so every query below
#    comes back invalid. Every box straddles world z = -1.4 instead, to
#    guarantee the ray actually lands on it.
# 2. Settle time: TestWorld.place() teleports the player directly onto the
#    floor, and the very next physics frame launches it upward by roughly
#    0.4 m before gravity brings it back down -- confirmed by printing
#    global_position every frame with no obstacle in the world at all, so it
#    is not something this test's own geometry causes. It takes about 20
#    frames to settle back to its resting height (~0.9 m) and stay there, so
#    every query below waits step(30), with margin over that settle. A
#    shorter wait queries mid-launch, at an unpredictable height, and makes
#    an otherwise-correct box placement read as a miss.
#    tests/legacy/test_probes.gd also uses step(30), but that is not live
#    precedent to follow: tools/run_tests.ts runs GUT with `-gdir=res://tests`
#    and no `-ginclude_subdirs`, and tests/legacy/.gdignore keeps the
#    directory out of Godot's resource scan besides -- it never runs.

func _world_with_box(size: Vector3, at: Vector3) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	world["box"] = body
	world["box_at"] = at
	return world

func _place(world: Dictionary) -> void:
	TestWorld.place(world)
	world["box"].global_position = world["box_at"]

func test_a_hit_reports_the_obstacle_height_above_the_feet() -> void:
	# 1.0 m tall, straddling SurfaceDown's fixed forward reach (z = -1.4) so
	# the top-find ray actually lands on the box rather than the floor beyond.
	var world := _world_with_box(Vector3(2.0, 1.0, 0.6), Vector3(0.0, 0.5, -1.4))
	await step(1)
	_place(world)
	await step(30)
	var hit: Dictionary = world["player"].probes.vault_query()
	assert_true(hit["valid"], "the probe missed a waist-high box")
	assert_almost_eq(hit["height"], 1.0, 0.08, "reported height is not the box top above the feet")
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_hit_reports_how_far_ahead_the_obstacle_is() -> void:
	# The numerator of the time-to-obstacle lookahead. Without it the whole
	# variant table has nothing to divide by.
	var world := _world_with_box(Vector3(2.0, 1.0, 0.6), Vector3(0.0, 0.5, -1.5))
	await step(1)
	_place(world)
	await step(30)
	var hit: Dictionary = world["player"].probes.vault_query()
	assert_true(hit["valid"], "the probe missed the box")
	assert_gt(hit["distance"], 0.0, "distance was not reported")
	assert_true(hit["distance"] < 1.5, "distance is implausibly large: %f" % hit["distance"])
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_thin_obstacle_reads_as_vaultable_over() -> void:
	# 0.4 m deep, again straddling z = -1.4: its far face (-1.6) sits well
	# short of where the vault-over probe checks (top's z minus
	# vault_over_probe_distance, -1.9 at the defaults), so that probe lands on
	# open floor beyond the box.
	var world := _world_with_box(Vector3(2.0, 1.0, 0.4), Vector3(0.0, 0.5, -1.4))
	await step(1)
	_place(world)
	await step(30)
	var hit: Dictionary = world["player"].probes.vault_query()
	assert_true(hit["valid"], "the probe missed a thin box")
	assert_true(hit["vault_over"], "a thin obstacle with clear floor beyond did not read as vault-over")
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_deep_obstacle_reads_as_onto_only() -> void:
	# bVaultOnto is functionally the obstacle's THICKNESS: is there anywhere
	# to land on the far side, or only its own top? 4 m deep is far beyond
	# where the vault-over probe checks, so that probe lands back on the same
	# box's own top -- not a lower, genuinely different surface.
	var world := _world_with_box(Vector3(2.0, 1.0, 4.0), Vector3(0.0, 0.5, -2.8))
	await step(1)
	_place(world)
	await step(30)
	var hit: Dictionary = world["player"].probes.vault_query()
	assert_true(hit["valid"], "the probe missed a deep box")
	assert_true(not hit["vault_over"], "a deep obstacle wrongly read as vault-over")
	world["box"].queue_free()
	TestWorld.teardown(world)
	await step(1)
