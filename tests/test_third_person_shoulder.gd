extends ParkourTest

# A wall run borrows the other shoulder: on a left-hand wall the camera
# sits at the preset right-shoulder position for the duration, and vice
# versa, or the view sits inside the wall the whole time.
#
# The rig's collision probe already pulls the camera in when something is
# between it and the body, but pulling in is the wrong answer for a wall: it
# gives a shot pressed flat against a surface that will be there for the whole
# manoeuvre. Standing on the other side of the body is the right one.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## DO NOT set wall_side directly on the rig. Player feeds
## camera_rig.set_wall_side() every physics tick, so a value poked straight
## into the rig is overwritten by the next step.
func _set_wall(side: int) -> void:
	_world["player"].wall_side = side
	_world["player"].camera_rig.set_wall_side(side)

func _rig() -> CameraRig:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var rig: CameraRig = _world["player"].camera_rig
	rig.third_person = true
	return rig

## How far to the side of the body the camera sits, after letting the ease
## arrive. Positive is the right.
##
## STEPPED, not read straight off _third_person_position(). The crossing is
## eased -- see CameraConfig.third_person_shoulder_time -- so a value read on
## the same frame the wall appears is still on the old side, and a test that
## did that would be asserting against the ease rather than the choice.
func _across(rig: CameraRig) -> float:
	await step(40)
	return rig._third_person_position().x

func test_a_left_hand_wall_puts_the_camera_on_the_right() -> void:
	var rig: CameraRig = await _rig()
	_set_wall(-1)
	var across: float = await _across(rig)
	assert_gt(across, 0.0,
		"a left-hand wall left the camera at x %.2f" % across)

func test_a_right_hand_wall_puts_the_camera_on_the_left() -> void:
	var rig: CameraRig = await _rig()
	_set_wall(1)
	var across: float = await _across(rig)
	assert_lt(across, 0.0,
		"a right-hand wall left the camera at x %.2f" % across)

func test_the_player_s_own_shoulder_is_not_rewritten() -> void:
	# THE POINT OF NOT WRITING IT INTO _shoulder. That is the player's own
	# preference and it is persisted to disk -- a wall run must not quietly
	# change a setting, and it must come back on its own when the wall is gone.
	var rig: CameraRig = await _rig()
	# SET TO THE LEFT FIRST. The default preference is the RIGHT shoulder,
	# which is also what a left-hand wall borrows, so with the default this
	# test cannot tell a restored preference from a borrowed one.
	rig._shoulder = CameraRig.Shoulder.LEFT
	var chosen: int = rig.third_person_debug()["shoulder"]
	_set_wall(-1)
	assert_eq(rig.third_person_debug()["shoulder"], chosen,
		"a wall run rewrote the player's shoulder preference")
	var borrowed: float = await _across(rig)
	_set_wall(0)
	var restored: float = await _across(rig)
	assert_ne(signf(restored), signf(borrowed),
		"the camera stayed on the borrowed side after the wall")

func test_the_crossing_is_eased_rather_than_cut() -> void:
	# The over-shoulder crossing must be eased, not cut. A shot that jumps
	# across the body reads as a cut rather than as a camera move, and the
	# wall run swaps sides on its own -- nobody asked for that cut.
	var rig: CameraRig = await _rig()
	rig._shoulder = CameraRig.Shoulder.LEFT
	await step(10)
	var before: float = rig._third_person_position().x
	_set_wall(-1)
	await step(1)
	var after_one_tick: float = rig._third_person_position().x
	var whole_span: float = absf(_world["player"].config.camera.third_person_right) * 2.0
	assert_lt(absf(after_one_tick - before), whole_span * 0.5,
		"the camera crossed %.2f m of a %.2f m span in one tick"
		% [absf(after_one_tick - before), whole_span])
	# And it does get there.
	await step(40)
	assert_gt(rig._third_person_position().x, 0.0,
		"the camera never finished crossing")
