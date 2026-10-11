extends ParkourTest

# The first slice of the faithful port, end to end: the original's frame
# (controller, actions, automatic transitions, physics, TickSpecial), its
# SetMove semantics on a real body, and the results its formulas give in
# closed form. [ME:CONFIRMED decompile 15, N1, N2, N4] Structural invariants
# and the original's own arithmetic -- no tuning values.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()
	await step(1)

func _world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(20)
	return world

## A platform of `height` metres to walk off, its +Z edge at z = 0, standing
## on the fixture's floor.
func _ledge(world: Dictionary, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, height, 10.0)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, height * 0.5, -5.0)
	world["ledge"] = body
	return body

func _free_ledge(world: Dictionary) -> void:
	if world.has("ledge"):
		(world["ledge"] as Node).queue_free()

## [ME:CONFIRMED emulated 15.7] BaseJumpZ 630 uu/s under the falling
## integrator's doubled gravity: apex 630^2 / 3200 = 124 uu, airtime
## 2 * 630 / 1600 = 0.7875 s.
func test_a_flat_jump_peaks_at_1_24_m_and_lands_after_0_7875_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var y0: float = player.global_position.y
	var top: float = y0
	input.press_jump()
	var frames := 0
	for i in 90:
		await step(1)
		frames += 1
		top = maxf(top, player.global_position.y)
		if frames > 2 and player.physics == Move.PHYS_WALKING:
			break
	assert_almost_eq(top - y0, 1.24, 0.005, "the flat jump's apex")
	# Landing is found on the first frame whose sub-step reaches the floor:
	# 0.7875 s lies between frames 47 and 48.
	assert_true(frames == 48, "landed after %d frames, not the 48th" % frames)

## [ME:CONFIRMED decompile N2 §6] Jump keeps PHYS_Walking until StartJump,
## which sets Falling -- and setting Falling stamps EnterFallingHeight.
func test_the_jump_switches_to_falling_physics_and_stamps_the_take_off_height() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var y0: float = player.global_position.y
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP)
	assert_eq(player.physics, Move.PHYS_FALLING)
	assert_almost_eq(player.enter_falling_height, y0, 0.001, "EnterFallingHeight is not the take-off height")
	assert_almost_eq(player.last_jump_location.y, y0, 0.001)

## [ME:CONFIRMED decompile N4 §2.5] Jump's bCheckExitToFalling at -400 uu/s,
## asked in PrePhysics: the frame that starts below it is the frame Falling
## takes over. Falling records Jump as the move it came out of.
func test_a_jump_hands_to_falling_below_minus_400_uu_per_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_jump()
	var history: Array = []
	for i in 60:
		history.append(player.velocity.y)
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING, "the jump never became a fall")
	var at_switch: float = history[history.size() - 1]
	var before_switch: float = history[history.size() - 2]
	assert_lt(at_switch, -4.0, "Falling took over above -400 uu/s")
	assert_true(before_switch >= -4.0, "Jump ran a frame past -400 uu/s (%.3f)" % before_switch)
	var falling: Move = player.move_manager.move_for(Move.FALLING)
	assert_eq(falling.previous_move, Move.JUMP)

## [ME:CONFIRMED decompile 15.4, 15.7] Every landing is Landing, and an
## ordinary one sets Walking from inside Landing's own StartMove: both changes
## happen on the touchdown frame, and Walking's OldMovementState is Landing.
func test_an_ordinary_landing_passes_through_landing_into_walking_on_one_frame() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var changes: Array = []
	var frame := [0]
	player.move_manager.move_changed.connect(func(from: StringName, to: StringName) -> void:
		changes.append([frame[0], from, to]))
	input.press_jump()
	for i in 90:
		await step(1)
		frame[0] += 1
		if player.move_manager.current_name == Move.WALKING and frame[0] > 2:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING)
	assert_eq(player.old_movement_state, Move.LANDING, "Walking was not entered from Landing")
	var into_landing: Array = changes.filter(func(c: Array) -> bool: return c[2] == Move.LANDING)
	var into_walking: Array = changes.filter(func(c: Array) -> bool: return c[2] == Move.WALKING)
	assert_eq(into_landing.size(), 1)
	assert_eq(into_walking.size(), 1)
	assert_eq(into_landing[0][0], into_walking[0][0], "Landing outlived its frame")
	assert_eq(player.physics, Move.PHYS_WALKING)

## [ME:CONFIRMED decompile 15.4] The forced Walking frame runs
## Walking.StartMove, which clears the wall-run jump's ledge ban.
func test_walking_start_clears_the_illegal_ledge_timer() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_jump()
	await step(5)
	player.illegal_ledge_timer = 2.0
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.illegal_ledge_timer, 0.0, "landing into Walking left the ledge ban running")

## [ME:CONFIRMED decompile N4 §1.2] A SetMove with bCheckCanDo that fails
## still writes PendingMovementState, and while it differs from the move
## TdPawn.CanDoMove refuses everything. The next successful SetMove ends it.
func test_a_refused_checked_set_move_leaves_pending_behind() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var manager: MoveManager = player.move_manager
	var falling: Move = manager.move_for(Move.FALLING)
	falling.last_stop_move_time = player.world_time
	falling.cfg.redo_move_time = 10.0
	assert_false(manager.set_move(Move.FALLING, true), "a cooling-down Falling was set")
	assert_eq(manager.current_name, Move.WALKING)
	assert_eq(player.pending_movement_state, Move.FALLING)
	assert_false(manager.pawn_can_do(Move.JUMP), "CanDoMove answered with a stale Pending")
	assert_true(manager.set_move(Move.JUMP))
	assert_eq(player.pending_movement_state, Move.JUMP)
	falling.cfg.redo_move_time = 0.0

## [ME:CONFIRMED decompile N1 §2.1] No walkable floor: the walking physics sets
## Falling, then SetMove(Falling, check) -- and the fall height starts at the
## edge.
func test_walking_off_an_edge_sets_falling_physics_and_move() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	_ledge(world, 3.0)
	player.global_position = Vector3(0.0, 3.0 + 0.95, -1.0)
	player.rotation.y = PI
	await step(10)
	input.hold_move(0.0, 1.0)
	var height_at_edge: float = player.global_position.y
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING)
	assert_eq(player.physics, Move.PHYS_FALLING)
	assert_almost_eq(player.enter_falling_height, height_at_edge, 0.02)
	_free_ledge(world)

## [ME:CONFIRMED decompile 15.4] Falling.StartMove after Walking: a body
## moving backwards with a body height of room below drops straight down.
func test_backing_off_an_edge_drops_straight_down() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	_ledge(world, 3.0)
	player.global_position = Vector3(0.0, 3.0 + 0.95, -1.0)
	await step(10)
	input.hold_move(0.0, -1.0)
	var walking_speed: float = 0.0
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
		walking_speed = player.horizontal_speed()
	assert_eq(player.move_manager.current_name, Move.FALLING)
	assert_gt(walking_speed, 3.0, "test setup: not walking backwards")
	assert_lt(player.horizontal_speed(), 0.5, "backing off the edge kept its speed")
	_free_ledge(world)

## [ME:CONFIRMED decompile 15.6] After a jump's fall the landing caps the
## horizontal speed at PreJumpMomentum - 65 uu/s. Read as Landing hands on:
## the walking physics then runs the rest of the touchdown frame on it.
func test_a_jumps_landing_caps_the_speed_at_its_take_off_speed() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(90)
	input.press_jump()
	await step(1)
	input.hold_move(0.0, 0.0)
	var jump: Move = player.move_manager.move_for(Move.JUMP)
	var airborne_speed: float = player.horizontal_speed()
	var at_landing := [-1.0]
	player.move_manager.move_changed.connect(func(_from: StringName, to: StringName) -> void:
		if to == Move.LANDING:
			at_landing[0] = player.horizontal_speed())
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.move_manager.move_for(Move.FALLING).previous_move, Move.JUMP)
	assert_gt(airborne_speed, jump.pre_jump_momentum, "test setup: the jump took no nudge")
	assert_almost_eq(float(at_landing[0]), jump.pre_jump_momentum - 0.65, 0.001, \
		"the landing speed is not PreJumpMomentum - LandingSpeedReduction")

## [ME:CONFIRMED decompile 15.6] A hard landing holds the body with move and
## look input ignored until it ends, then sets Walking.
func test_a_hard_landing_holds_the_body_with_input_ignored() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.global_position.y += player.config.pawn.hard_landing_height + 1.0
	player.move_manager.start(Move.FALLING)
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	var landing: Move = player.move_manager.move_for(Move.LANDING)
	assert_eq(player.move_manager.current_name, Move.LANDING)
	assert_eq(landing.kind, LandingMove.Kind.HARD)
	assert_true(player.ignore_move_input and player.ignore_look_input)
	await step(int(player.config.landing.lockout_time * 60.0) + 2)
	assert_eq(player.move_manager.current_name, Move.WALKING)
	assert_false(player.ignore_move_input or player.ignore_look_input, "the hold outlived Landing")

## [ME:CONFIRMED decompile 15.3] Walking + jump asks DodgeJump first: a full
## strafe (the hint at its maximum) is a dodge, forward is a jump.
func test_walking_jump_asks_dodge_jump_before_jump() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(-1.0, 0.0)
	await step(3)
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP)

## [ME:CONFIRMED decompile 15.2] PlayerWalking's tap: input released inside
## 0.15 s stops the body at 35 uu/s for 0.25 s.
func test_a_tap_stops_the_body_at_35_uu_per_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(5)
	input.hold_move(0.0, 0.0)
	await step(3)
	assert_almost_eq(player.horizontal_speed(), 0.35, 0.02, "the tap did not stop at 35 uu/s")

## [ME:CONFIRMED emulated 15.2, N1 §3] The sprint from rest follows the
## SpeedCurve the acceleration curve is built from: 520 uu/s at 1 s, 720 uu/s
## at 7 s, give or take what the friction the acceleration adds back leaves
## over.
func test_a_sprint_from_rest_follows_the_speed_curve() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(60)
	assert_almost_eq(player.horizontal_speed(), 5.2, 0.15, "speed after 1 s of sprinting")
	await step(360)
	assert_almost_eq(player.horizontal_speed(), 7.2, 0.15, "speed after 7 s of sprinting")
