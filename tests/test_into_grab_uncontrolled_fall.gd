extends ParkourTest

# [ME:CONFIRMED 11 §11.2] IntoGrab is one of the SIX states holding
# bCheckExitToUncontrolledFalling -- 180TurnInAir, AirBarge, Coil, Falling,
# IntoGrab, Stumble. Falling and Coil are the other two this project has, and
# both check; the capability matrix is what says IntoGrab must too.
#
# WHY IT MATTERS HERE AND NOT ONLY AS A TICKBOX. IntoGrab's approach phase
# carries the body under its own gravity while it waits for a hand to arrive,
# and touching() measures HORIZONTAL distance only -- so a body dropping fast
# down the face of a wall stays "still approaching" the whole way down without
# ever arriving. Measured on a 40 m block: committed at y = 18.75 and still in
# IntoGrab at y = 1.15, twenty metres later, because nothing in that state
# tests how far it had fallen. An unsurvivable drop arrived survivable, in a
# grab pose.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.has("box") and is_instance_valid(_world["box"]):
		_world["box"].queue_free()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A tall block whose top is a grabbable lip, and a body dropping past its face
## fast enough that the hands never arrive.
func _dropping_past_a_lip() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 40.0, 2.0)
	shape.shape = box
	block.add_child(shape)
	get_tree().root.add_child(block)
	_world["box"] = block
	await step(1)
	TestWorld.place(_world)
	# Top at y = 20, near face at z = -1.0.
	block.global_position = Vector3(0.0, 0.0, -2.0)
	await step(5)
	var player: Player = _world["player"]
	player.global_position = Vector3(0.0, 22.0, -0.4)
	# Baselines the fall counter HERE rather than at the spawn point, so the
	# height the test reasons about is the height the body really falls.
	player.set_grounded(true)
	player.velocity = Vector3(0.0, -18.0, 0.0)
	player.move_manager.start(Move.FALLING)
	return player

func test_a_reach_committed_mid_drop_still_goes_uncontrolled() -> void:
	var player: Player = await _dropping_past_a_lip()
	var committed := false
	var went_uncontrolled := false
	# Sampled as it goes: the counter is reset by the landing, so reading it
	# after the loop would report zero however far the body actually fell.
	var deepest := 0.0
	for _i in 200:
		await step(1)
		deepest = maxf(deepest, player.fall_tracker.fall_height)
		if player.move_manager.current_name == Move.INTO_GRAB:
			committed = true
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			went_uncontrolled = true
			break
		if player.global_position.y < 1.0:
			break
	assert_true(committed,
		"test setup: the drop never committed to a reach, so nothing was being tested")
	assert_true(went_uncontrolled,
		"a %.1f m drop stayed survivable because IntoGrab was holding the body"
			% deepest)
