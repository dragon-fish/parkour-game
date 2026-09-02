extends ParkourTest

# A respawn trigger of any shape. ✅ THE OWNER: "任意形状的触发器，走进去就保存
# 最后一个点（或者可以写顺序...）" -- the shipped rule is the hybrid:
# the last checkpoint walked through is where the next respawn happens,
# and nothing else -- the owner noclip-tested the original: flying back and
# suiciding still respawned at the LAST one, so even its looping tutorial
# is plain last-touched-wins (loops just re-touch earlier triggers).

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _extra: Array[Node] = []

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	return _world["player"]

func _checkpoint(at: Vector3) -> Checkpoint:
	var checkpoint := Checkpoint.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	shape.shape = box
	checkpoint.add_child(shape)
	checkpoint.position = at + Vector3.UP * 1.0
	get_tree().root.add_child(checkpoint)
	_extra.append(checkpoint)
	return checkpoint

func test_walking_in_saves_the_point() -> void:
	var player: Player = await _standing_player()
	assert_null(player.active_checkpoint, "test setup: a checkpoint was already active")
	var checkpoint := _checkpoint(player.global_position)
	await step(3)
	assert_eq(player.active_checkpoint, checkpoint, "standing inside the volume did not save it")

func test_the_last_touched_checkpoint_wins() -> void:
	# Touch one, then another, then walk back into the FIRST -- the first is
	# active again. This re-touching is exactly what makes the original's
	# looping tutorial look nearest-based without being it.
	var player: Player = await _standing_player()
	var first := _checkpoint(player.global_position)
	await step(3)
	assert_eq(player.active_checkpoint, first, "test setup: first touch did not register")
	first.position = Vector3(40.0, 1.0, 0.0)
	var second := _checkpoint(player.global_position)
	await step(3)
	assert_eq(player.active_checkpoint, second, "a later touch did not take over")
	second.position = Vector3(40.0, 1.0, 8.0)
	first.position = player.global_position
	await step(3)
	assert_eq(player.active_checkpoint, first,
		"walking back into an earlier checkpoint did not re-activate it")



func test_the_checkpoint_survives_a_reset() -> void:
	var player: Player = await _standing_player()
	var checkpoint := _checkpoint(player.global_position)
	await step(3)
	player.reset_state()
	assert_eq(player.active_checkpoint, checkpoint,
		"a reset forgot the checkpoint -- surviving resets is what one is FOR")

func test_a_named_checkpoint_announces_and_an_unnamed_one_stays_quiet() -> void:
	# 「检查点 xx 已保存」 -- shown only when the author gave the point a name,
	# and only when the active respawn actually changes.
	var player: Player = await _standing_player()
	# The corner TOAST, not the subtitle: a checkpoint is a report that
	# something happened, not the game talking to the player.
	var toast := Toast.new()
	add_child_autofree(toast)
	await step(1)
	player.toast = toast

	var silent := _checkpoint(player.global_position)
	await step(3)
	assert_eq(player.active_checkpoint, silent, "test setup: the unnamed touch did not register")
	assert_eq(toast.count(), 0, "an unnamed checkpoint put text on screen")

	silent.position = Vector3(40.0, 1.0, 0.0)
	var named := _checkpoint(player.global_position)
	named.display_name = "天台"
	await step(3)
	assert_eq(player.active_checkpoint, named, "test setup: the named touch did not register")
	assert_eq(toast.count(), 1, "a named checkpoint showed nothing")
	assert_true(toast.texts()[0].contains("天台"),
		"the line does not carry the name: %s" % [toast.texts()])

func test_a_dying_body_saves_nothing() -> void:
	# ✅ THE OWNER: jumping off a roof onto a checkpoint turned the death
	# into a teleport. Reached-alive is what a checkpoint records.
	var player: Player = await _standing_player()
	player.set_dying(true)
	var checkpoint := _checkpoint(player.global_position)
	await step(3)
	assert_null(player.active_checkpoint, "a dying body saved a checkpoint")
	player.set_dying(false)
	# Alive again in the same volume: Area3D only signals on ENTRY, so
	# re-touching needs a fresh entry -- step out and back in.
	checkpoint.position += Vector3(0.0, 0.0, 40.0)
	await step(2)
	checkpoint.position = player.global_position
	await step(3)
	assert_eq(player.active_checkpoint, checkpoint,
		"the same checkpoint refused an honest, living touch afterwards")

func test_a_higher_index_takes_over_from_a_lower_one() -> void:
	# Climbing: each point up the spiral outranks the one below it.
	var player: Player = await _standing_player()
	var low := _checkpoint(player.global_position)
	low.index = 10
	await step(3)
	assert_eq(player.active_checkpoint, low, "test setup: the low point did not register")
	low.position = Vector3(40.0, 1.0, 0.0)
	var high := _checkpoint(player.global_position)
	high.index = 20
	await step(3)
	assert_eq(player.active_checkpoint, high, "a higher index did not take over")

func test_a_lower_index_does_not_take_over() -> void:
	# Falling: the body drops back through the points it already passed. Those
	# touches must not undo the climb -- this is the whole reason index exists.
	var player: Player = await _standing_player()
	var high := _checkpoint(player.global_position)
	high.index = 20
	high.display_name = "顶端"
	await step(3)
	assert_eq(player.active_checkpoint, high, "test setup: the high point did not register")
	high.position = Vector3(40.0, 1.0, 0.0)
	var low := _checkpoint(player.global_position)
	low.index = 10
	await step(3)
	assert_eq(player.active_checkpoint, high,
		"falling back through a lower checkpoint undid the progress above it")
