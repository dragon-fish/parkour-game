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

## Runs up to speed, plants a kerb ahead, slides into it, and records every
## move the manager passes through on the way.
func _slide_over_kerb(height: float) -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 150:
		await step(1)

	# Wide enough that the run below never reaches the far edge: stepping OFF
	# a narrow kerb is a legitimate Falling, and this measures the step UP.
	var kerb_z: float = player.global_position.z - 2.0
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, height, 6.0)
	shape.shape = box
	body.add_child(shape)
	tree.root.add_child(body)
	body.global_position = Vector3(0.0, height * 0.5, kerb_z - 3.0)
	await step(1)

	input.press_crouch()
	await step(2)
	var entered: bool = player.move_manager.current_name == Move.SLIDE
	var seen: Array[StringName] = []
	# Long enough to mount the step and settle on top of it, short enough that
	# the far edge (6 m away) is never reached.
	for i in 25:
		await step(1)
		var now: StringName = player.move_manager.current_name
		if seen.is_empty() or seen[seen.size() - 1] != now:
			seen.append(now)
	return {"world": world, "kerb": body, "entered": entered, "seen": seen}

func test_a_slide_over_a_kerb_is_not_interrupted() -> void:
	# Reported from play and confirmed by the HUD transition log:
	#   Walking -> Slide -> Falling -> Grab -> Falling -> Walking
	# Riding over a low kerb lifts the body clear of the floor for a tick, and
	# SlideMove reads that single tick as "walked off a ledge" and bails to
	# Falling -- which then finds the same kerb and grabs it. The slide is not
	# BLOCKED by the kerb; it is CANCELLED by it.
	var r: Dictionary = await _slide_over_kerb(0.30)
	check(r["entered"], "test setup is wrong: never entered the slide")
	var seen: Array = r["seen"]
	check(not seen.has(Move.FALLING), \
		"riding a 0.30 m kerb dropped the slide into Falling (saw %s)" % [seen])
	r["kerb"].queue_free()
	TestWorld.teardown(r["world"])
	await step(1)


