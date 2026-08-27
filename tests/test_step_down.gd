extends ParkourTest

# Rooftop litter with a SLOPED face (normals 0.89-0.99) is correctly refused
# by try_step_up() as a ramp and handed to move_and_slide(), which climbs it
# -- and riding up and off it throws the body clear of the floor for a tick.
# Every move that reads leaving the floor as a ledge exit then cancels itself:
#
#     Walking -> Slide -> Falling -> Grab -> Falling -> Walking
#
# The slide is neither blocked nor mis-stepped; it is thrown.

const TestWorld = preload("res://tests/world_fixture.gd")

## A low wedge across the player's path: a ramp up to `height`, then nothing.
## Riding off its top edge is what throws the body.
func _add_wedge(z: float, height: float, run: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, height, run)
	shape.shape = box
	body.add_child(shape)
	# Tilted so its top face is a shallow ramp rather than a step, which is
	# what makes try_step_up() hand it to move_and_slide().
	body.rotation.x = -atan2(height, run)
	get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, height * 0.4, z)
	return body

func _ride_over_wedge() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 150:
		await step(1)

	# 0.25 m over a 0.5 m run is 26.6 degrees, i.e. a face normal of 0.894 --
	# matching the litter meshes the report came from (0.89 to 0.99). A gentler
	# wedge is climbed without ever leaving the floor and proves nothing.
	var wedge := _add_wedge(player.global_position.z - 2.0, 0.25, 0.5)
	await step(1)
	input.press_crouch()
	await step(2)
	var entered: bool = player.move_manager.current_name == Move.SLIDE

	var seen: Array[StringName] = []
	for i in 60:
		await step(1)
		var now: StringName = player.move_manager.current_name
		if seen.is_empty() or seen[seen.size() - 1] != now:
			seen.append(now)
	return {"world": world, "wedge": wedge, "entered": entered, "seen": seen}

func test_riding_off_low_clutter_does_not_cancel_the_slide() -> void:
	var r: Dictionary = await _ride_over_wedge()
	assert_true(r["entered"], "test setup is wrong: never entered the slide")
	assert_true(not (r["seen"] as Array).has(Move.FALLING), \
		"riding off a 0.25 m wedge threw the slide into Falling (saw %s)" % [r["seen"]])
	r["wedge"].queue_free()
	TestWorld.teardown(r["world"])
	await step(1)

func test_a_real_fall_is_still_a_fall() -> void:
	# The guard rail: try_step_down() must not catch a body that has genuinely
	# left the ground, or walking off a roof would never fall.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += 3.0
	await step(5)
	assert_true(player.move_manager.current_name == Move.FALLING, \
		"a body lifted well clear of the floor did not fall")
	TestWorld.teardown(world)
	await step(1)

func test_walking_down_a_flight_of_steps_never_leaves_the_floor() -> void:
	# DO NOT let try_step_down() move the body by hand and then snap without a
	# gap for the snap to detect: that leaves the body flush against the floor
	# with is_on_floor() never refreshed, so the caller hands off to Falling
	# anyway even on an ordinary staircase of 0.3 m steps -- Walking/Falling
	# flickering the whole way down.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Four steps down, each 0.3 m, laid out ahead of the player.
	var steps: Array[StaticBody3D] = []
	for i in 4:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.0, 4.0, 1.5)
		shape.shape = box
		body.add_child(shape)
		get_tree().root.add_child(body)
		# Tops at 1.2, 0.9, 0.6, 0.3 -- a descending flight.
		var top: float = 1.2 - 0.3 * i
		body.global_position = Vector3(0.0, top - 2.0, player.global_position.z - 1.5 - 1.5 * i)
		steps.append(body)
	# Stand on the top step before setting off.
	player.global_position.y = 1.2 + 1.0
	player.global_position.z -= 1.5
	await step(30)
	assert_true(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: never settled onto the top step")

	input.state.move = Vector2(0.0, 1.0)
	var airborne_ticks := 0
	for i in 150:
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			airborne_ticks += 1
	assert_true(airborne_ticks == 0, \
		"walking down 0.3 m steps went airborne on %d tick(s)" % airborne_ticks)

	for body in steps:
		body.queue_free()
	TestWorld.teardown(world)
	await step(1)
