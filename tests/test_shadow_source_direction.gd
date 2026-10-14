extends ParkourTest

# Where the ambient term of the player's modulated shadow comes from: the pawn
# points the light environment's AmbientShadowSourceDirection itself.
# [ME:CONFIRMED TdGame.u TdPlayerPawn.Tick, SetAmbientShadowDirection,
# ResetAmbientShadowDirection, TdMove_Grab.StartMove/StopMove; N3 §6]

const TestWorld = preload("res://tests/world_fixture.gd")

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
	await step(1)


func _start() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = at
	_extra.append(body)
	return body


func test_in_the_open_it_comes_from_above_and_a_tenth_behind_her() -> void:
	var player: Player = await _start()
	await step(2)
	var expected := (Vector3.UP * 10.0 - player.facing()).normalized()
	assert_almost_eq(player.ambient_shadow_source_direction.distance_to(expected), 0.0, 1e-4)


func test_against_a_wall_it_comes_out_of_the_wall() -> void:
	var player: Player = await _start()
	# The fixture's player faces -Z; the wall's face looks back along +Z.
	_box(Vector3(2.0, 2.0, 0.5), Vector3(0.0, 1.0, -0.65))
	await step(15)
	assert_eq(player.against_wall_state(), Player.AW_AGAINST_WALL, "test setup: not against the wall")
	var expected := (Vector3(0.0, 0.0, 1.0) + Vector3.UP * 0.1).normalized()
	assert_almost_eq(player.ambient_shadow_source_direction.distance_to(expected), 0.0, 1e-3)


func test_a_shadow_altering_move_holds_it_until_it_lets_go() -> void:
	var player: Player = await _start()
	player.set_ambient_shadow_direction(Vector3.RIGHT, true)
	await step(3)
	assert_eq(player.ambient_shadow_source_direction, Vector3.RIGHT, "the tick overrode the move")
	player.reset_ambient_shadow_direction(true)
	assert_false(player.in_shadow_altering_move_state)
	await step(1)
	assert_gt(player.ambient_shadow_source_direction.y, 0.99, "the tick did not take it back")


func test_hanging_it_comes_out_of_the_ledge_wall() -> void:
	var player: Player = await _start()
	var grab: Move = player.move_manager.move_for(Move.GRAB)
	player.move_normal = Vector3.RIGHT
	grab.enter(Move.WALKING)
	assert_eq(player.ambient_shadow_source_direction, Vector3.RIGHT)
	assert_true(player.in_shadow_altering_move_state)
	grab.exit()
	assert_false(player.in_shadow_altering_move_state, "letting go kept the hold")
