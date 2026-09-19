extends ParkourTest

# A lift car's zone counts only while the whole capsule is inside it: counting
# from a first touch at the door sent the car off before the player was in.

## A world with a 2.4 x 2.6 x 2.4 m zone standing on the floor at the origin,
## the player settled at `x`. Returns whether the zone fired within 1.5 s.
func _used_standing_at(x: float, whole: bool) -> bool:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	player.global_position = Vector3(x, player.global_position.y, 0.0)
	var zone := UseZone.new()
	zone.require_whole_body = whole
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.6, 2.4)
	shape.shape = box
	zone.add_child(shape)
	zone.position = Vector3(0.0, 1.3, 0.0)
	var fired := [false]
	zone.used.connect(func() -> void: fired[0] = true)
	get_tree().root.add_child(zone)
	await step(90)
	zone.queue_free()
	TestWorld.teardown(world)
	await step(1)
	return fired[0]

func test_a_body_half_inside_does_not_count_when_the_whole_body_is_required() -> void:
	# Capsule radius 0.4 at x = 1.0 reaches 1.4, past the box's 1.2.
	assert_false(await _used_standing_at(1.0, true), "a body half out of the car was counted")
	assert_true(await _used_standing_at(0.0, true), "a body wholly inside the car was never counted")

func test_a_touch_counts_when_the_whole_body_is_not_required() -> void:
	assert_true(await _used_standing_at(1.0, false), "a plain zone ignored a body overlapping it")
