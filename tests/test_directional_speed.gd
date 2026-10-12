extends ParkourTest

# The arc: the original runs at full speed only within 90 degrees of straight
# ahead, and at 14.4 km/h outside it. [ME:CONFIRMED decompile 15.2] It is
# PlayerWalking's sprint test, aForward > 0.7: straight ahead and both
# diagonals sprint, a sideways run walks and settles at SpeedMaxBaseVelocity.

func _world() -> Dictionary:
	return TestWorld.build(get_tree(), MovementConfig.new())

func _settle(world: Dictionary) -> void:
	await step(1)
	TestWorld.place(world)
	await step(2)

func test_running_straight_ahead_is_not_held_to_base_speed() -> void:
	var world := _world()
	await _settle(world)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
	var player: Player = world["player"]
	# Compared against the LATERAL cap, not against ground_speed: how close a
	# straight run gets to 7.2 takes longer than this test runs. What is pinned here is that the arc does not bind.
	assert_gt(player.horizontal_speed(), player.config.pawn.speed_max_base_velocity + 1.0, \
		"forward was held down as though it were outside the arc")
	TestWorld.teardown(world)
	await step(1)

func test_running_sideways_settles_at_base_speed() -> void:
	var world := _world()
	await _settle(world)
	# Straight left: 90 degrees off the facing, outside the arc whatever
	# forward_arc_deg is set to short of 90.
	world["input"].state.move = Vector2(-1.0, 0.0)
	for i in 200:
		await step(1)
	var player: Player = world["player"]
	assert_almost_eq(player.horizontal_speed(), player.config.pawn.speed_max_base_velocity, 0.2, \
		"sideways was not held to the lateral speed")
	TestWorld.teardown(world)
	await step(1)

func test_the_air_is_not_held_to_the_arc() -> void:
	# THE INVARIANT THIS FILE EXISTS FOR. The original limits the ground and
	# leaves the air alone -- backwards with S and space passes 18 km/h there.
	# Applying the arc to the air as well would look like a tidy-up and would
	# silently take that away.
	var world := _world()
	await _settle(world)
	var player: Player = world["player"]
	# Thrown backwards faster than the ground would ever allow, and airborne.
	var backwards: Vector3 = player.global_transform.basis.z
	backwards.y = 0.0
	var launch: float = player.config.pawn.speed_max_base_velocity + 2.0
	player.velocity = backwards.normalized() * launch
	player.velocity.y = player.config.pawn.base_jump_z
	world["input"].state.move = Vector2(0.0, -1.0)
	for i in 20:
		await step(1)
	assert_false(player.grounded, "test setup is wrong -- the body never left the ground")
	assert_gt(player.horizontal_speed(), player.config.pawn.speed_max_base_velocity + 0.5, \
		"the air was held to the ground's lateral cap")
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_cannot_be_entered_backwards() -> void:
	# [ME:CONFIRMED] Owner: the original refuses a slide sideways or backwards.
	var world := _world()
	await _settle(world)
	var player: Player = world["player"]
	# Fast enough to slide, but travelling the wrong way to be allowed one.
	var backwards: Vector3 = player.global_transform.basis.z
	backwards.y = 0.0
	player.velocity = backwards.normalized() * (player.config.slide.slide_abort_speed + 2.0)
	world["input"].state.move = Vector2(0.0, -1.0)
	await step(1)
	world["input"].press_crouch()
	await step(2)
	assert_ne(player.move_manager.current_name, Move.SLIDE, \
		"a backwards slide was allowed")
	TestWorld.teardown(world)
	await step(1)
