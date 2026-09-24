extends ParkourTest

# A loose box goes back where the level placed it on a respawn, whether or not
# physics props are on at the time.

var _nodes: Array[Node] = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await step(1)

## A floor and a 0.4 m box resting on it at the origin.
func _box() -> PhysicsProp:
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(40.0, 1.0, 40.0)
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(floor_shape)
	get_tree().root.add_child(ground)
	_nodes.append(ground)
	var box := PhysicsProp.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(0.4, 0.4, 0.4)
	box.add_child(shape)
	box.position = Vector3(0.0, 0.2, 0.0)
	get_tree().root.add_child(box)
	_nodes.append(box)
	return box

func test_a_respawn_puts_a_shoved_box_back() -> void:
	var box := _box()
	await step(2)
	box.linear_velocity = Vector3(8.0, 3.0, 0.0)
	await step(40)
	assert_gt(box.global_position.x, 1.0, "the shove did not move the box, so the reset proves nothing")
	box.reset_for_respawn()
	await step(10)
	assert_lt(box.global_position.distance_to(Vector3(0.0, 0.2, 0.0)), 0.05, "a respawn left the box where it was shoved to")

func test_a_respawn_puts_it_back_with_physics_props_off_too() -> void:
	var box := _box()
	await step(2)
	box.linear_velocity = Vector3(8.0, 3.0, 0.0)
	await step(40)
	box.simulate(false)
	box.reset_for_respawn()
	await step(2)
	assert_lt(box.global_position.distance_to(Vector3(0.0, 0.2, 0.0)), 0.05, "a respawn with props off left the box out of place")
	box.simulate(true)
	await step(10)
	assert_lt(box.global_position.distance_to(Vector3(0.0, 0.2, 0.0)), 0.05, "turning props back on threw the box out of place again")
