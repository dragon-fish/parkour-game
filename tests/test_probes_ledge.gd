extends ParkourTest

# ledge_query()'s ANCHOR, as distinct from its detection range.
#
# The two are separate questions and this file exists because conflating them
# shipped a real bug. ledge_find_distance (3.5 m, the confirmed
# TdPawn.LedgeFindDistance) is how far ahead the forward ray may LOOK. It is
# not where the ledge is: a raycast reports its first hit, so the forward ray
# stays correct at any search radius. SurfaceDown does not -- _query_surface()
# plants it at a FIXED forward offset and fires straight down, so feeding it
# the search radius aims it 3.5 m ahead of the body no matter where the wall
# actually stands.
#
# That hit is `edge`, and GrabMove uses `edge` as BOTH the hang anchor and the
# mantle target (see its own _edge). An anchor that ignores the obstacle's real
# distance means hanging in open air, missing close-in ledges entirely (the ray
# sails past a shallow ledge onto the floor behind it), and a 0.42 s mantle
# that lerps the body several metres horizontally through whatever is in
# between -- ScriptedMove drives the body directly, with no collision.
#
# Nothing in the running suite covered this, which is exactly why it shipped
# green: tests/legacy/test_ledge.gd and tests/legacy/test_probes.gd are
# archived and never run.
#
# Box placement and settle time follow tests/test_probes_vault.gd's own notes:
# TestWorld.place() launches the player briefly before it settles, so a query
# fired too early reads from an unpredictable height.

## Both blocks are DEEP on purpose. A deep block is what makes the bug visible
## rather than merely fatal: a shallow one would simply be missed (the fixed
## probe overshoots onto the floor and the query returns invalid, which reads
## as "no ledge here" and could be blamed on the fixture). A block that extends
## well past the fixed 3.5 m offset instead comes back VALID with an anchor
## that is the same for every obstacle distance -- the actual defect, stated
## directly.
const BLOCK_SIZE := Vector3(4.0, 2.2, 6.0)

## 2.2 m tall with the feet at y = 0, so the ledge top sits inside
## [min_wall_height 1.8, ledge_max_height 2.8] at both distances -- the height
## gate is not what either case is testing.
func _world_with_ledge(near_face_z: float) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BLOCK_SIZE
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	world["box"] = body
	# Forward is -Z, so a near face at -near_face_z puts the centre half a
	# block deeper still.
	world["box_at"] = Vector3(0.0, BLOCK_SIZE.y * 0.5, -near_face_z - BLOCK_SIZE.z * 0.5)
	return world

func _query_at(world: Dictionary) -> Dictionary:
	TestWorld.place(world)
	world["box"].global_position = world["box_at"]
	await step(30)
	return world["player"].probes.ledge_query()

func _teardown(world: Dictionary) -> void:
	world["box"].queue_free()
	TestWorld.teardown(world)

func test_the_grab_anchor_tracks_the_obstacle_it_actually_found() -> void:
	# A wall at 1 m and a wall at 2.5 m. Same height, same depth, same
	# everything except how far away they are.
	var near := _world_with_ledge(1.0)
	await step(1)
	var near_hit: Dictionary = await _query_at(near)
	assert_true(near_hit["valid"], "the probe missed a grabbable ledge 1 m ahead")
	var near_anchor: float = -(near_hit["edge"] as Vector3).z
	_teardown(near)
	await step(1)

	var far := _world_with_ledge(2.5)
	await step(1)
	var far_hit: Dictionary = await _query_at(far)
	assert_true(far_hit["valid"], "the probe missed a grabbable ledge 2.5 m ahead")
	var far_anchor: float = -(far_hit["edge"] as Vector3).z
	_teardown(far)
	await step(1)

	# THE POINT: two different obstacles must not produce one anchor. A fixed
	# forward offset gives the same number for both, whatever that number is.
	assert_gt(far_anchor - near_anchor, 1.0, \
		"the grab anchor did not move with the obstacle -- near %f vs far %f" % [near_anchor, far_anchor])

	# ...and each anchor must sit just past its OWN face, not somewhere the
	# body would swing to. The tolerance is deliberately loose: what the margin
	# past the face should be is a judgement call (see Probes.LEDGE_ANCHOR_
	# MARGIN), and pinning it exactly here would make this test a restatement
	# of that constant rather than a check that the anchor found the wall.
	assert_almost_eq(near_anchor, 1.0, 0.35, "the near ledge's anchor is not near its own face")
	assert_almost_eq(far_anchor, 2.5, 0.35, "the far ledge's anchor is not near its own face")
