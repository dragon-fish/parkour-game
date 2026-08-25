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
