extends ParkourTest

# [ME:INFERRED 12 §12.5] A soft pad is a collision box with a property, not a
# trigger: the original has one with no trigger anywhere near it, and a pad
# reached from an ordinary height behaves exactly like ordinary floor. The
# model that explains both is that an uncontrolled fall is a PREDICTION about
# where the body is going to land, and a predicted landing on something soft
# is never fatal.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

## A player settled on the floor, and the config it was built with.
func _settled() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world

## Puts a slab under the player's feet and hands back the body, so a test can
## make it soft or leave it hard.
func _slab_under(player: Player, drop: float) -> StaticBody3D:
	var slab := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	slab.add_child(shape)
	add_child_autofree(slab)
	slab.global_position = player.global_position + Vector3(0.0, -drop, 0.0)
	return slab

## Lifts the body to a height that is certainly fatal and starts the fall.
func _drop_from_lethal(player: Player) -> void:
	player.global_position.y += player.config.pawn.falling_uncontrolled_height + 6.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)

## Runs the fall out, stopping early if it turns fatal.
func _fall_until_settled(player: Player) -> void:
	for i in 300:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			return
		if player.grounded:
			return

func test_a_fatal_fall_onto_ordinary_ground_still_kills() -> void:
	# The control. Without it every assertion below could pass on a fall that
	# was never deep enough to be fatal in the first place.
	var world := await _settled()
	var player: Player = world["player"]
	_slab_under(player, 1.0)
	await _drop_from_lethal(player)
	await _fall_until_settled(player)
	assert_eq(player.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"test setup: this drop was survivable, so nothing below proves anything")

func test_a_pad_under_a_fatal_fall_is_never_reached_as_a_death() -> void:
	var world := await _settled()
	var player: Player = world["player"]
	_slab_under(player, 1.0).add_to_group(Probes.SOFT_LANDING_GROUP)
	await _drop_from_lethal(player)
	await _fall_until_settled(player)
	assert_ne(player.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"the pad was under the body the whole way down and it died anyway")

func test_a_pad_absorbs_the_landing_as_well_as_the_death() -> void:
	# One rule, not two. The drop is treated as though it never happened, so
	# there is no landing cost to pay and no roll to have missed -- a pad the
	# player has to roll off is a pad that punishes being rescued.
	var world := await _settled()
	var player: Player = world["player"]
	_slab_under(player, 1.0).add_to_group(Probes.SOFT_LANDING_GROUP)
	await _drop_from_lethal(player)
	await _fall_until_settled(player)
	assert_true(player.grounded, "test setup: the body never reached the pad")
	assert_almost_eq(player.last_landing_fall_height, 0.0, 0.001, \
		"the pad let the fall through to the landing rules")

func test_the_reprieve_is_rechecked_rather_than_latched() -> void:
	# Falling still has air control, so a body reprieved at the top can leave
	# the pad on the way down. Simulated by taking the pad away, which is the
	# same thing from the prediction's side and does not depend on how hard
	# the air can be steered.
	var world := await _settled()
	var player: Player = world["player"]
	var pad := _slab_under(player, 1.0)
	pad.add_to_group(Probes.SOFT_LANDING_GROUP)
	await _drop_from_lethal(player)
	await step(6)
	assert_ne(player.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"test setup: the reprieve never took")
	pad.remove_from_group(Probes.SOFT_LANDING_GROUP)
	await _fall_until_settled(player)
	assert_eq(player.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"the reprieve was decided once and never revisited")
