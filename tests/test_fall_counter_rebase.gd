extends ParkourTest

# MoveConfig.fall_counts_from_exit: a move that leaves the body somewhere the
# take-off never was hands the fall counter a new start at its exit.

const TestWorld = preload("res://tests/world_fixture.gd")
const LEDGE_TOP := 2.0
const LEDGE_FACE_Z := -1.5
const EDGE := Vector3(0.0, LEDGE_TOP, -1.6)

var _world: Dictionary = {}
var _extra: Array[Node] = []

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func test_a_pull_up_out_of_a_long_drop_owes_nothing_on_top() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, LEDGE_TOP, 3.0)
	shape.shape = box
	body.add_child(shape)
	player.get_parent().add_child(body)
	body.global_position = Vector3(0.0, LEDGE_TOP * 0.5, LEDGE_FACE_Z - 1.5)
	_extra.append(body)
	player.rotation.y = 0.0
	var query := {"valid": true, "edge": EDGE, "top": EDGE,
			"normal": Vector3.UP, "face_normal": Vector3(0, 0, 1)}
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.pending_ledge = query
	# As if the hands had caught the ledge at the end of a 6 m drop.
	player.fall_tracker.reset(player.global_position.y + 6.0)
	player.move_manager.start(Move.GRAB)
	await step(1)
	assert_gt(player.fall_tracker.fall_height, 5.0, "test setup: the hang did not carry the drop")
	_world["input"].state.move = Vector2(0.0, 1.0)
	for i in 180:
		await step(1)
		if player.move_manager.current_name != Move.GRAB:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: never climbed over")
	assert_lt(player.fall_tracker.fall_height, 0.1,
		"the climb carried the drop below the ledge onto the top")
