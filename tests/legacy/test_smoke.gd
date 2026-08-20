extends ParkourTest

# Proves the harness itself works: the physics server advances and a body
# added at runtime actually falls and lands.

func test_physics_server_advances() -> void:
	var before := Engine.get_physics_frames()
	await step(5)
	var after := Engine.get_physics_frames()
	assert_gt(float(after), float(before), "physics frame counter did not advance")

func test_body_falls_and_lands() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	get_tree().root.add_child(floor_body)

	var body := CharacterBody3D.new()
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.0
	capsule.radius = 0.4
	body_shape.shape = capsule
	body.add_child(body_shape)
	get_tree().root.add_child(body)

	# Nodes are not in-tree until a frame elapses; setting global_position
	# before this point silently fails with an is_inside_tree() error.
	await step(1)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	body.global_position = Vector3(0.0, 5.0, 0.0)

	for i in 200:
		body.velocity.y -= 24.0 * (1.0 / 60.0)
		body.move_and_slide()
		await step(1)
		if body.is_on_floor():
			break

	assert_true(body.is_on_floor(), "body never landed on the floor")
	assert_almost_eq(body.global_position.y, 1.0, 0.05, "resting height wrong")

	body.queue_free()
	floor_body.queue_free()
	await step(1)
