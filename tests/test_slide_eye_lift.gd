extends ParkourTest

# The per-model slide eye lift has to come back down.
#
# ✅ THE OWNER: "滑铲结束后没有恢复相机位置，应该在「滑铲起身」动作期间逐渐还原
# 相机位置，现在只要滑铲过相机将永久抬升0.15."
#
# CROUCH IS HELD AT 1.0 THROUGHOUT, which is not what Player does but is what
# isolates the thing under test. The slide's own camera drop is several times
# larger than the lift, and it eases on a different clock; letting it move
# during the measurement buries a 0.15 m signal under a 0.66 m one. The lift's
# release does not depend on the crouch amount anyway -- Player zeroes the lift
# itself, and `lift_target = _eye_lift * _crouch_amount` is 0 either way.

const FRAME := 1.0 / 60.0
const LIFT := 0.15

func _rig() -> CameraRig:
	var player: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	var config := MovementConfig.new()
	player.setup(config, ScriptedInputSource.new())
	player.camera_rig.setup(config)
	return player.camera_rig

func _run(rig: CameraRig, seconds: float) -> void:
	for i in int(seconds / FRAME):
		rig.update_effects(FRAME, 0.0, true)

## Drives the rig into a settled slide with no lift applied, and returns the eye
## height there -- the baseline the lift is measured against.
func _settled_slide(rig: CameraRig) -> float:
	rig.set_crouch_amount(1.0)
	rig.set_eye_lift(0.0)
	_run(rig, 1.0)
	return rig.position.y

func test_the_lift_is_fully_released_after_the_stand_up() -> void:
	var rig := await _rig()
	await step(1)
	var without_lift := _settled_slide(rig)

	rig.set_eye_lift(LIFT)
	_run(rig, 1.0)
	assert_almost_eq(rig.position.y - without_lift, LIFT, 0.005,
		"the lift never went on, so the release below would prove nothing")

	# What Player does the instant the move stops being SLIDE.
	rig.set_eye_lift(0.0)
	var release: float = MovementConfig.new().camera.eye_lift_release_time
	_run(rig, release * 3.0)
	assert_almost_eq(rig.position.y, without_lift, 0.001,
		"the eye is still %.3f m up, %.1f s after the slide ended" \
			% [rig.position.y - without_lift, release * 3.0])

func test_the_release_takes_about_as_long_as_it_is_told_to() -> void:
	# A TIME, not a rate -- see CameraConfig.eye_lift_release_time, which exists
	# so the same half second applies to every body whatever its lift is. The
	# bounds are wide because this asserts the SHAPE of the release: not a snap,
	# not a stall. The curve itself is a look value and is nobody's business
	# here (docs/feel-backlog.md 57).
	var rig := await _rig()
	await step(1)
	var without_lift := _settled_slide(rig)

	rig.set_eye_lift(LIFT)
	_run(rig, 1.0)

	var release: float = MovementConfig.new().camera.eye_lift_release_time
	rig.set_eye_lift(0.0)
	_run(rig, release * 0.5)
	var remaining := rig.position.y - without_lift
	assert_lt(remaining, LIFT * 0.85,
		"half way through the release the eye has barely moved (%.3f of %.3f left)" % [remaining, LIFT])
	assert_gt(remaining, LIFT * 0.15,
		"the eye dropped almost the whole way in half the time -- that is a cut, not a release")
