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
const BODY_PATH := "res://assets/models/test.vrm"
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

func test_the_model_owns_the_eye_and_the_procedural_drop_yields() -> void:
	# REVERSES AN EARLIER FIX, on the owner's rule: "the camera serves the
	# PICTURE, not the correctness of the numbers -- the model's neck during a
	# slide is well below the collision capsule, and that is fine."
	#
	# The bug was never that the model drove the eye. It was that BOTH did: the
	# procedural slide drop and the animation's own, stacked, put the eye 43 cm
	# under the floor. The first fix silenced the model, which is the wrong one
	# of the two to silence -- the animation is what knows where the body
	# actually is.
	#
	# SETTLED FIRST, because that drop eases: two update_effects() calls in a
	# row advance it, and an earlier version measured 0.150 m of easing and
	# blamed the head.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(20)
	var rig: CameraRig = (world["player"] as Player).camera_rig
	const TICK := 1.0 / 60.0

	for i in 90:
		rig.set_crouch_amount(1.0)
		rig.set_head_offset(Vector3.ZERO)
		rig.update_effects(TICK, 0.0, true)
	var settled: float = rig.position.y

	rig.set_crouch_amount(1.0)
	rig.set_head_offset(Vector3(0.0, -1.0, 0.0))
	rig.update_effects(TICK, 0.0, true)
	assert_lt(rig.position.y, settled - 0.9, 		"at full crouch the model's own drop no longer reaches the eye")

func test_without_a_body_the_procedural_drop_still_happens() -> void:
	# The drop is a stand-in for a body that is not there. Handing the job to
	# the model must not leave a body-less setup with no crouch at all -- which
	# is every level in this project that has no character in it.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	var rig: CameraRig = player.camera_rig
	assert_null(player.body, "the fixture attached a body, so this proves nothing")

	const TICK := 1.0 / 60.0
	for i in 90:
		rig.set_crouch_amount(0.0)
		rig.update_effects(TICK, 0.0, true)
	var standing: float = rig.position.y
	for i in 90:
		rig.set_crouch_amount(1.0)
		rig.update_effects(TICK, 0.0, true)
	assert_lt(rig.position.y, standing - 0.5, 		"a body-less crouch dropped the eye only %.3f m" % (standing - rig.position.y))

func test_the_per_model_lift_raises_the_crouched_eye() -> void:
	# NOT A FUDGE FOR A BAD ASSET -- the price of a correct decision, which the
	# owner spotted themselves: being blocked by the chest means the camera is
	# at the NECK rather than the eyes, which is where an FPS camera belongs. A
	# neck-height eye is inside the ribcage the moment the body goes prone, and
	# the slide clip is genuinely prone.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	var rig: CameraRig = player.camera_rig
	const TICK := 1.0 / 60.0
	const LIFT := 0.3

	for i in 120:
		rig.set_crouch_eye_lift(0.0)
		rig.set_crouch_amount(1.0)
		rig.update_effects(TICK, 0.0, true)
	var without: float = rig.position.y

	for i in 120:
		rig.set_crouch_eye_lift(LIFT)
		rig.set_crouch_amount(1.0)
		rig.update_effects(TICK, 0.0, true)
	assert_almost_eq(rig.position.y - without, LIFT, 0.005, \
		"the lift raised the crouched eye by %.3f m instead of %.3f" \
		% [rig.position.y - without, LIFT])

func test_the_lift_does_nothing_while_standing() -> void:
	# It is a correction for a pose, not a change to the eye height. Leaking
	# into the standing camera would quietly break the 1.66 m the whole feel is
	# calibrated against.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(20)
	var rig: CameraRig = (world["player"] as Player).camera_rig
	const TICK := 1.0 / 60.0

	for i in 120:
		rig.set_crouch_eye_lift(0.0)
		rig.set_crouch_amount(0.0)
		rig.update_effects(TICK, 0.0, true)
	var without: float = rig.position.y
	for i in 120:
		rig.set_crouch_eye_lift(0.3)
		rig.set_crouch_amount(0.0)
		rig.update_effects(TICK, 0.0, true)
	assert_almost_eq(rig.position.y, without, 0.001, \
		"a standing eye moved %.3f m for a crouch-only correction" % (rig.position.y - without))
