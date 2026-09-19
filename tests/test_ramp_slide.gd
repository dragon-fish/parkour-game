extends ParkourTest

# The seated chute slide (TdMove_RumpSlide) starts on a surface in the
# uncontrolled_slide group and nowhere else: the same 50 degree ramp without
# the group is an ordinary too-steep slope. Structural invariants only; the
# speeds are dials.

const TestWorld = preload("res://tests/world_fixture.gd")

## A 20 m ramp rising toward -Z with its foot at the origin, tilted `angle`.
func _add_ramp(angle_deg: float, chute: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.5, 20.0)
	shape.shape = box
	body.add_child(shape)
	if chute:
		body.add_to_group(Probes.UNCONTROLLED_SLIDE_GROUP, true)
	get_tree().root.add_child(body)
	var a := deg_to_rad(angle_deg)
	body.rotation.x = a
	body.global_position = Vector3(0.0, 10.0 * sin(a) - 0.25, -10.0 * cos(a))
	return body

## Drops the player onto the ramp `s` metres up its face and returns the
## moves seen over `ticks`, in order, with repeats collapsed. `floor_y` is
## where the fixture's floor waits under the ramp's foot.
func _ride(angle_deg: float, chute: bool, ticks: int, s: float = 6.0, floor_y: float = -30.0) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	# The fixture's floor would catch the body under the ramp's foot.
	world["floor"].global_position.y = floor_y
	var player: Player = world["player"]
	var ramp := _add_ramp(angle_deg, chute)
	var a := deg_to_rad(angle_deg)
	player.global_position = Vector3(0.0, s * sin(a) + 1.3, -s * cos(a))
	player.velocity = Vector3.ZERO
	var seen: Array[StringName] = []
	var lowest := player.global_position.y
	for i in ticks:
		await step(1)
		lowest = minf(lowest, player.global_position.y)
		var now: StringName = player.move_manager.current_name
		if seen.is_empty() or seen[seen.size() - 1] != now:
			seen.append(now)
	return {"world": world, "ramp": ramp, "seen": seen, "player": player, "lowest": lowest}

func _finish(r: Dictionary) -> void:
	r["ramp"].queue_free()
	TestWorld.teardown(r["world"])
	await step(1)

func test_a_marked_chute_starts_the_ramp_slide_and_carries_the_body_down() -> void:
	var r: Dictionary = await _ride(50.0, true, 90)
	var seen: Array = r["seen"]
	assert_true(seen.has(Move.RAMP_SLIDE), "landing on a marked chute never entered RampSlide (saw %s)" % [seen])
	var player: Player = r["player"]
	assert_true(r["lowest"] < 3.0, "the slide did not carry the body down the chute (lowest y %.2f)" % r["lowest"])
	# Down the chute is +Z here: the body travelled along the surface, not
	# straight down through it.
	assert_true(player.global_position.z > -4.0, "the body did not travel along the chute (z %.2f)" % player.global_position.z)
	await _finish(r)

func test_the_same_slope_without_the_mark_is_not_a_ramp_slide() -> void:
	var r: Dictionary = await _ride(50.0, false, 60)
	var seen: Array = r["seen"]
	assert_false(seen.has(Move.RAMP_SLIDE), "an unmarked 50 degree slope started RampSlide (saw %s)" % [seen])
	await _finish(r)

func test_a_long_descent_lands_hard_on_the_floor_at_the_foot() -> void:
	# From 18 m up a 50 degree ramp the body drops 13.8 m along it, past
	# hard_landing_descent, onto a floor just under the foot: the landing is
	# the hard one, though the fall after the chute is a few centimetres.
	var r: Dictionary = await _ride(50.0, true, 240, 18.0, -0.5)
	var seen: Array = r["seen"]
	assert_true(seen.has(Move.RAMP_SLIDE), "never on the chute (saw %s)" % [seen])
	assert_true(seen.has(Move.LANDING), "a 13 m chute slide onto the floor did not land hard (saw %s)" % [seen])
	await _finish(r)

func test_a_short_descent_runs_off_the_foot() -> void:
	# From 6 m up the same ramp the descent is 4.6 m: the runner keeps going.
	var r: Dictionary = await _ride(50.0, true, 240, 6.0, -0.5)
	var seen: Array = r["seen"]
	assert_true(seen.has(Move.RAMP_SLIDE), "never on the chute (saw %s)" % [seen])
	assert_false(seen.has(Move.LANDING), "a 4.6 m chute slide landed hard (saw %s)" % [seen])
	assert_true(seen.has(Move.WALKING), "the slide never handed back to the runner (saw %s)" % [seen])
	await _finish(r)

func test_the_slide_declares_its_grounding_every_tick() -> void:
	# MoveManager enforces the declaration on the first tick; this pins that
	# the fall counter is reset while on the chute, so the chute's end and
	# not its top is where a fall is measured from.
	var r: Dictionary = await _ride(50.0, true, 40)
	var player: Player = r["player"]
	if player.move_manager.current_name == Move.RAMP_SLIDE:
		assert_true(player.fall_tracker.fall_height < 1.0,
			"fall height accrued on the chute: %.2f" % player.fall_tracker.fall_height)
	else:
		assert_true((r["seen"] as Array).has(Move.RAMP_SLIDE), "never on the chute (saw %s)" % [r["seen"]])
	await _finish(r)
