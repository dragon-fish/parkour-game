class_name TestSlideStepUp
extends TestCase

# try_step_up() was called from WalkingMove and nowhere else. Slide and Crouch
# got no step allowance at all, so the same ankle-high clutter a standing body
# walks over could stop them dead.
#
# WHAT THIS CAN AND CANNOT SHOW. A capsule's rounded bottom rolls over a low
# kerb unaided IF it is moving fast enough, so a fast slide clears 0.34 m with
# or without the call -- that path proves nothing either way. The step
# allowance is load-bearing at LOW speed, which is what a crouched walk is, so
# that is what this measures.

const TestWorld = preload("res://tests/world_fixture.gd")

func _crouch_into_kerb(height: float) -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	var kerb_z: float = player.global_position.z - 1.0
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, height, 0.4)
	shape.shape = box
	body.add_child(shape)
	tree.root.add_child(body)
	body.global_position = Vector3(0.0, height * 0.5, kerb_z)
	await step(1)

	input.press_crouch()
	await step(3)
	var crouched: bool = player.move_manager.current_name == Move.CROUCH
	input.state.move = Vector2(0.0, 1.0)
	for i in 180:
		await step(1)
	return {"world": world, "kerb": body, "crouched": crouched, \
		"kerb_z": kerb_z, "end_z": player.global_position.z}

func test_a_crouched_walk_rides_over_ankle_high_clutter() -> void:
	var r: Dictionary = await _crouch_into_kerb(0.30)
	check(r["crouched"], "test setup is wrong: never entered the crouch")
	check(r["end_z"] < r["kerb_z"] - 0.3, \
		"a crouched walk was stopped by a 0.30 m kerb (kerb at %.2f, reached %.2f)" \
			% [r["kerb_z"], r["end_z"]])
	r["kerb"].queue_free()
	TestWorld.teardown(r["world"])
	await step(1)
