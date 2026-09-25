extends ParkourTest

# The take-off and landing nod is presentation. It runs while the player can
# act, so it must never steer what the player is aiming at.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_nod_does_not_move_the_aim() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	var rig: CameraRig = world["player"].camera_rig
	rig.set_pitch(0.0)
	rig.kick_pitch(deg_to_rad(10.0), 0.15, 0.5)
	await step(9)
	var shown := -rig.camera.global_transform.basis.z
	assert_gt(shown.y, 0.05, "test setup: the nod never tipped the view")
	assert_almost_eq(rig.aim_forward().y, 0.0, 0.01, "the nod moved the aim with the view")
	TestWorld.teardown(world)
