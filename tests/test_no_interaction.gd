extends ParkourTest

# The no_interaction group: geometry the body may stand on and nothing else.
#
# What every case here does is A/B THE SAME GEOMETRY. The box is built once,
# queried, then put in the group and queried again -- so a failure can only be
# the tag, never the placement. Placement is the hard part of a probe test and
# it is borrowed wholesale from test_probes_vault.gd: a box straddling world
# z = -1.4, because SurfaceDown fires at a fixed forward reach and a box short
# of it lets the ray sail onto the floor beyond; and step(30) to settle, because
# TestWorld.place() teleports the body and the next frame launches it ~0.4 m.
#
# THE POINT OF THE LAST CASE IS THAT IT PASSES. An inert surface still has to
# be seen by the landing prediction -- walking over the top is the one thing
# the group leaves working, and a fall onto one that reported open air below
# would turn every drop onto an air wall into an uncontrolled fall.

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	if _world.has("box") and is_instance_valid(_world["box"]):
		_world["box"].queue_free()
	TestWorld.teardown(_world)
	_world = {}

## A box the player is standing in front of, settled and ready to query.
func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	_world["box"] = body
	await step(1)
	TestWorld.place(_world)
	body.global_position = at
	await step(30)
	return body

func _probes() -> Probes:
	return _world["player"].probes

## THE GROUP GOES ON THE BODY, not on the CollisionShape3D under it -- one tag
## covering every shape a body owns is the whole reason it is read off the
## collider the ray reports. Tagging the shape node instead is the mistake
## Arena warns about at load.
func _tag(body: StaticBody3D) -> void:
	body.add_to_group(Probes.NO_INTERACTION_GROUP)

func test_an_inert_box_is_not_vaultable() -> void:
	var box := await _box(Vector3(2.0, 1.0, 0.6), Vector3(0.0, 0.5, -1.4))
	assert_true(_probes().vault_query()["valid"], "test setup: the box was not vaultable to begin with")
	_tag(box)
	assert_false(_probes().vault_query()["valid"], "a vault was found on an inert box")

func test_an_inert_ledge_cannot_be_grabbed() -> void:
	# Tall enough that the ledge column finds a lip rather than a vault top.
	var box := await _box(Vector3(2.0, 2.2, 0.6), Vector3(0.0, 1.1, -1.4))
	assert_true(_probes().ledge_query()["valid"], "test setup: no ledge on the box to begin with")
	_tag(box)
	assert_false(_probes().ledge_query()["valid"], "a ledge was found on an inert box")

func test_an_inert_wall_ahead_is_not_climbable() -> void:
	# BUILT FAR AWAY AND WALKED IN AFTERWARDS, unlike the cases above. A wall
	# has to sit inside WallClimbConfig.check_distance (0.6 m) to be seen at
	# all, and a 4 m slab standing that close while the body settles simply
	# pushes it: measured, the player ends up 0.61 m BEHIND where it was placed
	# and the wall is then 1.06 m away, out of reach. So the slab is parked
	# clear, the body is left to settle, and only then is the slab moved to
	# 0.45 m in front of wherever the body actually came to rest.
	var box := await _box(Vector3(4.0, 4.0, 0.6), Vector3(0.0, 2.0, -8.0))
	var player: Player = _world["player"]
	box.global_position = Vector3(player.global_position.x, 2.0,
		player.global_position.z - 0.75)
	await step(2)
	assert_true(_probes().wall_ahead_query()["valid"], "test setup: no wall ahead to begin with")
	_tag(box)
	assert_false(_probes().wall_ahead_query()["valid"], "a climbable wall was found on an inert box")

func test_an_inert_surface_is_still_something_to_land_on() -> void:
	# The exemption, and the case that kills people if it regresses. Queried
	# from above the box rather than in front of it, which is where a landing
	# prediction is asked from.
	var box := await _box(Vector3(6.0, 1.0, 6.0), Vector3(0.0, 0.5, 0.0))
	_tag(box)
	_world["player"].global_position = Vector3(0.0, 5.0, 0.0)
	await step(1)
	var landing: Dictionary = _probes().predicted_landing(Vector3(0.0, -1.0, 0.0))
	assert_false(landing.is_empty(), "the landing prediction went blind to an inert surface")
	assert_eq(landing.get("collider"), box, "the prediction found something other than the box")

func test_the_group_is_reported_when_it_cannot_be_read() -> void:
	# Same load-time check the soft landing pads get, and the same CSG trap:
	# a brush inside a combiner owns no collision, so the tag on it is silent.
	var arena: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(arena)
	var root := CSGCombiner3D.new()
	root.use_collision = true
	var brush := CSGBox3D.new()
	brush.add_to_group(Probes.NO_INTERACTION_GROUP)
	root.add_child(brush)
	arena.add_child(root)
	assert_string_contains(arena._why_a_tag_cannot_be_read(brush), "brush inside a CSG tree")

	var body := StaticBody3D.new()
	arena.add_child(body)
	assert_eq(arena._why_a_tag_cannot_be_read(body), "", "a StaticBody3D was refused")
