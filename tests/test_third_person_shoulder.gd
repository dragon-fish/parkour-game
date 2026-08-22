extends ParkourTest

# A wall run borrows the other shoulder.
#
# ✅ THE OWNER: "on a left-hand wall, put the camera at the preset right
# shoulder for the duration, and the other way round -- otherwise the view sits
# inside the wall the whole time."
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

func _rig() -> CameraRig:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var rig: CameraRig = _world["player"].camera_rig
	rig.third_person = true
	return rig

## How far to the side of the body the camera sits. Positive is the right.
func _across(rig: CameraRig) -> float:
	return rig._third_person_position().x

func test_a_left_hand_wall_puts_the_camera_on_the_right() -> void:
	var rig: CameraRig = await _rig()
	rig.set_wall_side(-1)
	assert_gt(_across(rig), 0.0,
		"a left-hand wall left the camera at x %.2f" % _across(rig))

func test_a_right_hand_wall_puts_the_camera_on_the_left() -> void:
	var rig: CameraRig = await _rig()
	rig.set_wall_side(1)
	assert_lt(_across(rig), 0.0,
		"a right-hand wall left the camera at x %.2f" % _across(rig))

func test_the_player_s_own_shoulder_is_not_rewritten() -> void:
	# THE POINT OF NOT WRITING IT INTO _shoulder. That is the player's own
	# preference and it is persisted to disk -- a wall run must not quietly
	# change a setting, and it must come back on its own when the wall is gone.
	var rig: CameraRig = await _rig()
	# ⚠️ SET TO THE LEFT FIRST. The default preference is the RIGHT shoulder,
	# which is also what a left-hand wall borrows -- so with the default this
	# test cannot tell a restored preference from a borrowed one, and the first
	# draft of it duly failed against correct code.
	rig._shoulder = CameraRig.Shoulder.LEFT
	var chosen: int = rig.third_person_debug()["shoulder"]
	rig.set_wall_side(-1)
	assert_eq(rig.third_person_debug()["shoulder"], chosen,
		"a wall run rewrote the player's shoulder preference")
	var borrowed: float = _across(rig)
	rig.set_wall_side(0)
	assert_ne(signf(_across(rig)), signf(borrowed),
		"the camera stayed on the borrowed side after the wall")
