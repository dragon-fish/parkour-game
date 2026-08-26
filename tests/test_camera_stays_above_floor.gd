extends ParkourTest

# The eye never goes under the floor, whatever the body's animation does.
#
# Reported during a slide: the camera went underground. The owner's guess was
# that the slide clip is simply very low, and it is -- measured, the head drops
# 1.27 m and ends 40 cm off the floor, a properly prone slide.
#
# But the fault was DOUBLE-COUNTING. This project already lowers the eye by
# slide_camera_drop, which is 0.81 and measured from the original; the head
# follow then added the animation's own 1.27 m on top. From a 1.62 m standing
# eye that lands 46 cm under the floor.
#
# Head-follow exists to keep the camera inside the skull. While a move owns the
# eye's height, the animation repeating that intent is not extra information --
# it is the same information counted twice.

const TestWorld = preload("res://tests/world_fixture.gd")
const BODY_PATH := "res://assets/models/local/test.vrm"
const ANIMS_PATH := "res://assets/animations/ual2_standard.glb"

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _floor_y(player: Player) -> float:
	return player.global_position.y - player.standing_height() * 0.5

func test_a_slide_keeps_the_eye_above_the_ground() -> void:
	# Runs with the real body when it is present and without one otherwise, so a
	# fresh clone still checks the drop itself rather than skipping.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	var player: Player = _world["player"]
	if ResourceLoader.exists(BODY_PATH):
		player.body_mount_rotation_degrees = Vector3(0.0, 180.0, 0.0)
		player.body_mount_offset = Vector3(0.0, 0.07, 0.06)
		player.body_mount_scale = 1.13
		if ResourceLoader.exists(ANIMS_PATH):
			player.body_animation_libraries = [load(ANIMS_PATH)]
		player.body_head_path = NodePath("GeneralSkeleton/Head")
		player._attach_body(load(BODY_PATH))
		await step(3)

	_world["input"].state.move = Vector2(0.0, 1.0)
	for i in 120:
		await step(1)
	_world["input"].press_crouch()

	var rig: CameraRig = player.camera_rig
	var lowest := 999.0
	for i in 90:
		await step(1)
		lowest = minf(lowest, rig.global_position.y - _floor_y(player))
	assert_gt(lowest, 0.15, \
		"the eye reached %.3f m above the floor during a slide" % lowest)
