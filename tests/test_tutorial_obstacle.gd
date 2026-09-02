extends ParkourTest

# Placement, following and locking. Distances and angles are tuning values and
# are not asserted -- what is asserted is that the obstacle is IN FRONT, that
# it follows only while unlocked, and that locking is absolute.

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

func _obstacle_for(player: Player) -> TutorialObstacle:
	var obstacle := TutorialObstacle.new()
	obstacle.player = player
	get_tree().root.add_child(obstacle)
	_extra.append(obstacle)
	return obstacle

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	return _world["player"]

func test_it_is_placed_in_front_of_the_player() -> void:
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	var forward: Vector3 = -player.global_transform.basis.z
	var to_obstacle: Vector3 = obstacle.anchor - player.global_position
	to_obstacle.y = 0.0
	assert_gt(forward.normalized().dot(to_obstacle.normalized()), 0.9,
		"the obstacle was not placed ahead of the player")

func test_it_follows_the_player_turning_while_unlocked() -> void:
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	var before: Vector3 = obstacle.anchor
	player.rotate_y(PI)
	await step(2)
	assert_gt(before.distance_to(obstacle.anchor), 1.0,
		"turning around did not move the unlocked obstacle")

func test_locking_pins_it_for_good() -> void:
	# THE HARD REQUIREMENT. Without it the player turns his head and watches
	# the obstacle drift through the void, and the level stops reading as a
	# place.
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	obstacle.lock()
	var pinned: Vector3 = obstacle.anchor
	player.rotate_y(PI)
	await step(4)
	assert_almost_eq(obstacle.anchor.distance_to(pinned), 0.0, 0.001,
		"a locked obstacle moved")

func test_it_keeps_its_distance_from_one_that_is_still_leaving() -> void:
	# The player finishing an obstacle and immediately turning round makes
	# "in front" point at the one that is still collapsing.
	var player: Player = await _standing_player()
	var leaving := _obstacle_for(player)
	await step(2)
	leaving.lock()
	var arriving := _obstacle_for(player)
	arriving.avoid = [leaving]
	player.rotate_y(PI)
	await step(4)
	assert_gt(arriving.anchor.distance_to(leaving.anchor), arriving.min_separation - 0.01,
		"a new obstacle was placed on top of one that had not left yet")

func test_a_wrap_carries_a_locked_obstacle_with_it() -> void:
	# Task 6 wires TorusWrap.wrapped to this. Asserted here because the
	# contract belongs to the obstacle.
	var player: Player = await _standing_player()
	var obstacle := _obstacle_for(player)
	await step(2)
	obstacle.lock()
	var before: Vector3 = obstacle.anchor
	obstacle.shift_by(Vector3(-100.0, 0.0, 0.0))
	assert_almost_eq(obstacle.anchor.x, before.x - 100.0, 0.01,
		"a locked obstacle did not travel with the wrap")
