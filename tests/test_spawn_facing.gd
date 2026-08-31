extends ParkourTest

# Which way a body faces when the level starts.
#
# A level whose spawn is turned to face its first obstacle should start the
# run looking at it. The marker is a Marker3D and the editor gizmo draws the
# arrow it is turned to, so the facing is something a level author sets and
# sees -- it just was not read.

var _arena: Node3D = null

func after_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null

func _arena_facing(yaw_degrees: float) -> Player:
	_arena = ArenaBuilder.new().build()
	get_tree().root.add_child(_arena)
	await step(1)
	_arena.spawn_point.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	_arena.reset_player()
	# reset_player() spans two physics frames by its own documentation, and the
	# body settles out of its spawn gap for a few more.
	await step(20)
	return _arena.player

func test_a_turned_spawn_turns_the_body() -> void:
	var player: Player = await _arena_facing(90.0)
	assert_almost_eq(player.rotation.y, deg_to_rad(90.0), 0.01, \
		"the spawn point's facing was thrown away")

func test_an_unturned_spawn_still_faces_forward() -> void:
	# The control: reading the marker must not invent a rotation of its own.
	var player: Player = await _arena_facing(0.0)
	assert_almost_eq(player.rotation.y, 0.0, 0.01)

func test_a_checkpoint_still_outranks_the_spawn() -> void:
	# Last-touched wins, facing included -- the rule the spawn branch was
	# missing, not one it should now take over.
	var player: Player = await _arena_facing(90.0)
	var checkpoint := Checkpoint.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	shape.shape = box
	checkpoint.add_child(shape)
	_arena.add_child(checkpoint)
	checkpoint.global_position = _arena.spawn_point.global_position
	checkpoint.rotation = Vector3(0.0, deg_to_rad(-45.0), 0.0)
	player.active_checkpoint = checkpoint
	_arena.reset_player()
	await step(20)
	assert_almost_eq(player.rotation.y, deg_to_rad(-45.0), 0.01, \
		"the spawn point's facing overrode the checkpoint's")
