extends ParkourTest

# TdFallHeightVolume.Touch [ME:CONFIRMED decompile]: a body entering the volume
# has EnterFallingHeight set to Center.Z + FallHeightOffset, and its current
# move is told. Structural only: the heights are made up, what is pinned is
# that the touch sets exactly the volume's value, that a volume switched off
# touches nothing, and that RumpSlide hears of it.

const TestWorld = preload("res://tests/world_fixture.gd")

const CENTER_Y := 6.0
const OFFSET := 1.5

## A 6 x 2 x 6 m volume centred at `at`, placed before it enters the tree.
func _volume(at: Vector3, size := Vector3(6.0, 2.0, 6.0)) -> FallHeightVolume:
	var volume := FallHeightVolume.new()
	volume.center_y = CENTER_Y
	volume.fall_height_offset = OFFSET
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	volume.add_child(shape)
	volume.position = at
	get_tree().root.add_child(volume)
	return volume

## Drops the player from 12 m through a volume at CENTER_Y and returns the
## EnterFallingHeight it carries once below the volume, still in the air.
func _fall_through(switched_off: bool) -> float:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	var volume := _volume(Vector3(0.0, CENTER_Y, 0.0))
	if switched_off:
		# What KismetRunner and PackagePresence do to a volume that is off.
		PackagePresence.set_colliding(volume, false)
	var player: Player = world["player"]
	player.global_position = Vector3(0.0, 12.0, 0.0)
	player.velocity = Vector3.ZERO
	player.fall_tracker.reset(player.global_position.y)
	player.enter_falling_height = player.global_position.y
	for i in 240:
		await step(1)
		if player.global_position.y < CENTER_Y - 2.0:
			break
	assert_lt(player.global_position.y, CENTER_Y - 2.0, "test setup: the body never fell past the volume")
	assert_gt(player.global_position.y, 2.0, "test setup: the body reached the floor, which resets the height")
	var height: float = player.enter_falling_height
	volume.queue_free()
	TestWorld.teardown(world)
	await step(1)
	return height

func test_falling_through_the_volume_measures_the_fall_from_its_height() -> void:
	var height: float = await _fall_through(false)
	assert_almost_eq(height, CENTER_Y + OFFSET, 0.001,
		"EnterFallingHeight is not the volume's Center.Z + FallHeightOffset")

func test_a_volume_switched_off_touches_nothing() -> void:
	var height: float = await _fall_through(true)
	assert_almost_eq(height, 12.0, 0.001, "a volume with its collision off still set the fall height")

## A 20 m ramp rising toward -Z with its foot at the origin, marked as a chute.
func _add_chute(angle_deg: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.5, 20.0)
	shape.shape = box
	body.add_child(shape)
	body.add_to_group(Probes.UNCONTROLLED_SLIDE_GROUP, true)
	var a := deg_to_rad(angle_deg)
	body.rotation.x = a
	body.position = Vector3(0.0, 10.0 * sin(a) - 0.25, -10.0 * cos(a))
	get_tree().root.add_child(body)
	return body

func test_a_rump_slide_through_the_volume_is_told() -> void:
	# RumpSlide.TouchedFallHeightVolume is what lets its landing be hard, and
	# what stops the slide re-measuring the fall from the chute every frame.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	world["floor"].global_position.y = -30.0
	var player: Player = world["player"]
	var a := deg_to_rad(50.0)
	var chute := _add_chute(50.0)
	# Over the chute's lower part, 2 m up its face; the body lands 6 m up.
	var volume := _volume(Vector3(0.0, 2.0 * sin(a), -2.0 * cos(a)), Vector3(6.0, 3.0, 3.0))
	player.global_position = Vector3(0.0, 6.0 * sin(a) + 1.3, -6.0 * cos(a))
	player.velocity = Vector3.ZERO
	player.fall_tracker.reset(player.global_position.y)
	player.enter_falling_height = player.global_position.y
	var rump = player.move_manager.move_for(Move.RAMP_SLIDE)
	var slid := false
	var told_while_sliding := false
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.RAMP_SLIDE:
			slid = true
			told_while_sliding = told_while_sliding or rump.touched_fall_height
	assert_true(slid, "test setup: the body never rump-slid")
	assert_true(told_while_sliding, "the slide passed through the volume and was never told")
	volume.queue_free()
	chute.queue_free()
	TestWorld.teardown(world)
	await step(1)
