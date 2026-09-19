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
	# Teleported up: the fall counter still holds the fixture floor as its
	# launch height, and would count nothing until the body fell below it.
	player.fall_tracker.reset(player.global_position.y)
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

func test_a_chute_gentle_enough_to_stand_on_still_carries_the_body_down() -> void:
	# 35 degrees is under Godot's floor_max_angle: a floor to move_and_slide(),
	# which walked the slide's press into the surface UP the chute. Escape's
	# slanted building is 38.
	var r: Dictionary = await _ride(35.0, true, 90)
	var seen: Array = r["seen"]
	assert_true(seen.has(Move.RAMP_SLIDE), "landing on a gentle marked chute never entered RampSlide (saw %s)" % [seen])
	# Placed at z -4.9; down the chute is +Z.
	var player: Player = r["player"]
	assert_true(player.global_position.z > -3.0, "the slide did not carry the body down a gentle chute (z %.2f)" % player.global_position.z)
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

## Drops the player from `drop` metres above a point on the chute and returns
## the moves seen plus the health at the end.
func _drop_onto(drop: float, ticks: int) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	world["floor"].global_position.y = -30.0
	var player: Player = world["player"]
	var ramp := _add_ramp(50.0, true)
	var a := deg_to_rad(50.0)
	var s := 6.0
	player.global_position = Vector3(0.0, s * sin(a) + 1.3 + drop, -s * cos(a))
	player.velocity = Vector3.ZERO
	player.fall_tracker.reset(player.global_position.y)
	var seen: Array[StringName] = []
	for i in ticks:
		await step(1)
		var now: StringName = player.move_manager.current_name
		if seen.is_empty() or seen[seen.size() - 1] != now:
			seen.append(now)
	return {"world": world, "ramp": ramp, "seen": seen, "player": player}

func test_a_hard_fall_onto_the_chute_costs_health_but_slides_on() -> void:
	# 7 m: past hard_landing_height (5.3), short of the uncontrolled tier.
	var r: Dictionary = await _drop_onto(7.0, 150)
	var seen: Array = r["seen"]
	var player: Player = r["player"]
	assert_true(seen.has(Move.RAMP_SLIDE), "a 7 m fall onto the chute did not slide (saw %s)" % [seen])
	assert_false(seen.has(Move.LANDING), "a fall onto the chute staggered instead of sliding (saw %s)" % [seen])
	assert_true(player.health.hp < player.config.pawn.max_health,
		"a 7 m fall onto the chute cost no health (hp %.0f)" % player.health.hp)
	await _finish(r)

func test_an_uncontrolled_fall_is_not_saved_by_the_chute() -> void:
	# 14 m: past falling_uncontrolled_height. The chute is a surface like any
	# other to a body already out of control.
	var r: Dictionary = await _drop_onto(14.0, 200)
	var seen: Array = r["seen"]
	var player: Player = r["player"]
	assert_true(seen.has(Move.FALL_UNCONTROLLED), "test setup is wrong: never lost control (saw %s)" % [seen])
	assert_false(seen.has(Move.RAMP_SLIDE), "an uncontrolled fall onto the chute slid instead of dying (saw %s)" % [seen])
	assert_true(player.is_dying() or player.health.is_dead(),
		"an uncontrolled fall onto the chute did not kill (hp %.0f)" % player.health.hp)
	await _finish(r)

func test_the_body_and_the_model_come_round_to_face_down_the_chute() -> void:
	# The ramp rises toward -Z, so facing -Z (yaw 0) is facing UP it. Downhill
	# is +Z, yaw PI. Placed facing uphill, the body and the drawn model both
	# end up facing the foot, and not within one tick.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	world["floor"].global_position.y = -30.0
	var player: Player = world["player"]
	var ramp := _add_ramp(50.0, true)
	var a := deg_to_rad(50.0)
	player.global_position = Vector3(0.0, 8.0 * sin(a) + 1.3, -8.0 * cos(a))
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.fall_tracker.reset(player.global_position.y)
	var entered_at := -1
	var yaw_one_tick_in := 0.0
	for i in 90:
		await step(1)
		if entered_at < 0 and player.move_manager.current_name == Move.RAMP_SLIDE:
			entered_at = i
		elif entered_at == i - 1:
			yaw_one_tick_in = absf(wrapf(player.rotation.y - PI, -PI, PI))
	assert_true(entered_at >= 0, "never entered RampSlide")
	assert_true(yaw_one_tick_in > deg_to_rad(90.0),
		"the view was cut round in one tick (%.0f degrees off downhill after one tick)" % rad_to_deg(yaw_one_tick_in))
	var off: float = absf(wrapf(player.rotation.y - PI, -PI, PI))
	assert_true(off < deg_to_rad(10.0), "the body did not come round to face down the chute (%.0f degrees off)" % rad_to_deg(off))
	var model_off: float = absf(wrapf(player.visual_yaw() - PI, -PI, PI))
	assert_true(model_off < deg_to_rad(10.0), "the model did not come round to face down the chute (%.0f degrees off)" % rad_to_deg(model_off))
	ramp.queue_free()
	TestWorld.teardown(world)
	await step(1)

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
