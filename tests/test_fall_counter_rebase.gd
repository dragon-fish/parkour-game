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

## A body hanging from the test ledge as if its hands had just stopped a drop
## of `fallen` metres.
func _caught_after(fallen: float) -> Player:
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
	player.fall_tracker.reset(player.global_position.y + fallen)
	# reset() only sets the start; a live fall has been update()d every tick
	# by the time the hands catch, and GrabMove.enter() reads it at once.
	player.fall_tracker.update(0.0, 0.0, player.global_position.y)
	player.move_manager.start(Move.GRAB)
	await step(1)
	return player

func test_a_pull_up_out_of_a_long_drop_owes_nothing_on_top() -> void:
	var player: Player = await _caught_after(6.0)
	assert_gt(player.fall_tracker.fall_height, 5.0, "test setup: the hang did not carry the drop")
	_world["input"].state.move = Vector2(0.0, 1.0)
	# Past the hard catch's lockout (HardCatch) and the climb after it.
	for i in 240:
		await step(1)
		if player.move_manager.current_name != Move.GRAB:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: never climbed over")
	assert_lt(player.fall_tracker.fall_height, 0.1,
		"the climb carried the drop below the ledge onto the top")

func test_a_hard_catch_on_a_ledge_pins_the_hang() -> void:
	# Past hard_landing_height the hands still catch, and the body hangs
	# through the hard landing's own lockout before it may climb.
	var player: Player = await _caught_after(player_hard_height() + 0.7)
	_world["input"].state.move = Vector2(0.0, 1.0)
	await step(30)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	assert_eq(player.move_manager.current_name, Move.GRAB, "a hard catch let go of the ledge")
	assert_false(grab.is_mantling(), "a hard catch climbed inside its lockout")
	await step(int(MovementConfig.new().landing.lockout_time * 60.0))
	assert_true(grab.is_mantling() or player.move_manager.current_name != Move.GRAB,
		"the climb never came once the lockout let go")

func test_an_ordinary_catch_climbs_at_once() -> void:
	var player: Player = await _caught_after(player_hard_height() - 1.0)
	_world["input"].state.move = Vector2(0.0, 1.0)
	await step(5)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	assert_true(grab.is_mantling(), "a catch short of a hard landing was pinned anyway")

func player_hard_height() -> float:
	return MovementConfig.new().pawn.hard_landing_height
