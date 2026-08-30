extends ParkourTest

# A body standing still holds its heading while the head and spine follow
# the view (HeadLook); past PawnConfig.turn_in_place_angle_deg the legs take
# one step round, on the pack's Turn90 clip. Both views. See
# Player._drive_body_yaw().

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func _standing_player(third_person: bool) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	var player: Player = _world["player"]
	player.camera_rig.third_person = third_person
	await step(20)
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: not standing")
	return player

func test_a_glance_inside_the_angle_leaves_the_body_where_it_was_in_first_person() -> void:
	var player: Player = await _standing_player(false)
	var heading: float = player.visual_yaw()
	player.rotation.y += deg_to_rad(60.0)
	await step(10)
	assert_almost_eq(wrapf(player.visual_yaw() - heading, -PI, PI), 0.0, 0.001,
		"a glance turned the whole body in first person")
	assert_false(player.is_turning_in_place(), "a glance inside the angle started a step round")

func test_looking_past_the_angle_steps_the_body_round_by_it() -> void:
	var player: Player = await _standing_player(false)
	var heading: float = player.visual_yaw()
	var angle: float = deg_to_rad(player.config.pawn.turn_in_place_angle_deg)
	player.rotation.y += angle + deg_to_rad(15.0)  # left of the heading
	await step(2)
	assert_true(player.is_turning_in_place(), "looking past the angle did not start a step round")
	assert_eq(String(player.turn_in_place_clip()), "Turn90_L",
		"looking left, the body stepped the other way (%s)" % String(player.turn_in_place_clip()))
	assert_almost_eq(player.turn_in_place_clip_scale(), player.config.pawn.turn_in_place_clip_scale, 0.001,
		"the step did not name the clip's own pace")
	assert_gt(player.turn_in_place_window(), 0.0, "the step has no window to turn over")
	await step(int(player.turn_in_place_window() * 60.0) + 8)
	# The clamp took the 15 degrees of excess at once, and the step the
	# remaining 90: the heading lands on the view.
	assert_almost_eq(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI), 0.0, 0.01,
		"the heading did not come round to the view in its own time")
	# The clip keeps going on its own clock after the heading has arrived.
	assert_true(player.is_turning_in_place(),
		"the turn clip was cut the moment the heading arrived")
	await step(int(Player.TURN_IN_PLACE_FALLBACK_CLIP_TIME * 60.0) + 5)
	assert_false(player.is_turning_in_place(), "the turn clip never ended")
	assert_almost_eq(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI), 0.0, 0.01,
		"the heading drifted after the step")

func test_third_person_keeps_its_heading_however_far_the_camera_goes() -> void:
	# The owner's own touch: from outside, the body holds and the camera
	# comes round to its face. No step round in third person.
	var player: Player = await _standing_player(true)
	var heading: float = player.visual_yaw()
	player.rotation.y -= deg_to_rad(150.0)
	await step(60)
	assert_false(player.is_turning_in_place(), "third person stepped round")
	assert_almost_eq(wrapf(player.visual_yaw() - heading, -PI, PI), 0.0, 0.001,
		"the body turned in third person while the player only looked")

func test_moving_cancels_the_step_and_the_run_catches_up() -> void:
	var player: Player = await _standing_player(false)
	var angle: float = deg_to_rad(player.config.pawn.turn_in_place_angle_deg)
	player.rotation.y += angle + deg_to_rad(15.0)
	await step(3)
	assert_true(player.is_turning_in_place(), "test setup: no step round began")
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	await step(2)
	assert_false(player.is_turning_in_place(), "movement did not cancel the step round")
	await step(30)
	assert_almost_eq(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI), 0.0, 0.05,
		"the run did not bring the body round to face the way it is going")

func test_a_flick_past_the_angle_drags_the_legs_round_at_once_in_first_person() -> void:
	# The owner: a little clipping beats seeing your own back. Whatever the
	# mouse does, the heading never falls further than the angle behind the
	# view in first person.
	var player: Player = await _standing_player(false)
	var angle: float = deg_to_rad(player.config.pawn.turn_in_place_angle_deg)
	player.rotation.y += deg_to_rad(175.0)
	await step(1)
	var behind: float = absf(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI))
	assert_true(behind <= angle + 0.001,
		"a flick left the legs %.0f degrees behind the view" % rad_to_deg(behind))
	# ...and the step then brings the rest round.
	await step(int(player.turn_in_place_window() * 60.0) + 5)
	behind = absf(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI))
	assert_lt(behind, deg_to_rad(20.0),
		"after the step the legs were still %.0f degrees behind" % rad_to_deg(behind))

func test_turning_on_steadily_takes_one_step_after_another() -> void:
	# The owner: turning right and keeping going only ever played one Turn90.
	# Each time the head runs out of range again is a new step, with its own
	# number for the animator to replay the clip on.
	var player: Player = await _standing_player(false)
	var angle: float = deg_to_rad(player.config.pawn.turn_in_place_angle_deg)
	player.rotation.y -= angle + deg_to_rad(5.0)
	await step(2)
	var first: int = player.turn_in_place_serial()
	assert_gt(first, 0, "test setup: no first step")
	await step(int(player.turn_in_place_window() * 60.0) + 8)
	# Keep turning the same way past the angle again.
	player.rotation.y -= angle + deg_to_rad(5.0)
	await step(2)
	assert_eq(player.turn_in_place_serial(), first + 1,
		"a second run past the angle did not count as a second step")

func test_a_spin_faster_than_the_step_never_puts_the_body_on_the_far_side() -> void:
	# Twenty degrees a tick, for a while: the heading must stay within the
	# angle behind the view on the short side every tick, never flip across.
	var player: Player = await _standing_player(false)
	var angle: float = deg_to_rad(player.config.pawn.turn_in_place_angle_deg)
	for i in 40:
		player.rotation.y += deg_to_rad(20.0)
		await step(1)
		var behind: float = absf(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI))
		assert_true(behind <= angle + 0.001,
			"tick %d: the legs were %.0f degrees off the view" % [i, rad_to_deg(behind)])
