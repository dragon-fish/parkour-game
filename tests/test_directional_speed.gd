extends ParkourTest

# The arc: the original runs at full speed only within 90 degrees of straight
# ahead, and at 14.4 km/h outside it. What these pin is the SHAPE of that rule,
# not the numbers -- the numbers are dials on PawnConfig and expected to move.

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
	# straight run gets to 7.2 is SpeedEnergy's business and takes longer than
	# this test runs. What is pinned here is that the arc does not bind.
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

func test_leaving_the_arc_lowers_the_ceiling_over_seconds_not_frames() -> void:
	# PENDING, and the reason is worth more than the test. Nothing caps
	# sideways speed in the original: the CEILING decays to base speed over
	# about 2.6 s and the body follows it down, still ACCELERATING a quarter
	# second in (see PawnConfig.speed_max_base_velocity for the capture).
	#
	# Here it arrives in one frame, and the decay is not what does it:
	# Player._charge_turn() bills the change of the wish direction, so
	# pressing A swings that vector 90 degrees in a single tick and
	# spend_turn() empties the budget straight to the floor. In the original
	# the same press moves the VIEW not at all -- yaw is constant across the
	# capture -- and speed climbs afterwards, so no such bill is charged.
	#
	# Billing facing instead of wish is the fix, and it lands on a pile of
	# turn tests that stand in for a turn by rotating input.move, where
	# facing never changes. That is its own piece of work.
	pending("charge_turn bills a keypress as a 90 degree turn -- see the comment")

func test_the_air_is_not_held_to_the_arc() -> void:
	# THE INVARIANT THIS FILE EXISTS FOR. The original limits the ground and
	# leaves the air alone -- backwards with S and space passes 18 km/h there.
	# Folding the arc into Player.speed_cap() would look like a tidy-up and
	# would silently take that away, because every airborne state reads it.
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
