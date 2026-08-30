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
	await step(int(player.turn_in_place_window() * 60.0) + 5)
	assert_false(player.is_turning_in_place(), "the step round never ended")
	assert_almost_eq(wrapf(player.visual_yaw() - heading, -PI, PI), angle, 0.01,
		"the body did not step round by the angle")
	# Fifteen degrees left for the head, well inside its range: no second step.
	await step(10)
	assert_false(player.is_turning_in_place(), "a second step began with the head inside its range")

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
