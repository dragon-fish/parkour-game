extends ParkourTest

# The wall family as ported from the original: the trace natives, the wall
# physics, the wall moves and the view's ConstrainAxis. [ME:CONFIRMED
# decompile N3, N4, 15.5, 15.10] Structural invariants and the results the
# original's own formulas give in closed form -- no tuning values.

const TestWorld = preload("res://tests/world_fixture.gd")
const UU := 0.01
const DT := 1.0 / 60.0

var _world: Dictionary = {}
var _extra: Array[Node] = []

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}
	await step(1)

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

func _box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	# Placed BEFORE it enters the tree: a body that spends a frame at the
	# origin is a floor the walking physics may take for its base.
	body.position = center
	get_tree().root.add_child(body)
	_extra.append(body)
	return body

## Faces the body (and its pawn yaw) along the Godot yaw `yaw`.
func _face(player: Player, yaw: float) -> void:
	player.rotation.y = yaw
	player.pawn_yaw = yaw

# --- ConstrainAxis ------------------------------------------------------------------

## [ME:CONFIRMED decompile TdMove.ConstrainAxis] Inside the window the input
## is cut at the edge; past 60 % of an edge it is scaled by what is left of
## the last 40 %.
func test_constrain_axis_cuts_and_damps_inside_the_window() -> void:
	assert_eq(CameraRig.constrain_axis(0, -1000, 1000, 0.1, 100), 100, "free input was touched")
	assert_eq(CameraRig.constrain_axis(900, -1000, 1000, 0.1, 500), 25,
		"cut at 1000, then damped by (1000 - 900) / 400")
	assert_eq(CameraRig.constrain_axis(900, -1000, 1000, 0.1, -500), -500,
		"an input away from the edge was damped")

## Outside the window the view is pulled back by the excess times dt / 0.2;
## an input coming back faster than that is let through, an outward one is
## replaced by the pull.
func test_constrain_axis_pulls_back_from_outside() -> void:
	var pull: int = int((1000 - 3000) * 0.25)
	assert_eq(CameraRig.constrain_axis(3000, -1000, 1000, 0.25, 0), pull, "no pull back")
	assert_eq(CameraRig.constrain_axis(3000, -1000, 1000, 0.25, -2000), -2000,
		"an input back toward the window faster than the pull was cut")
	assert_eq(CameraRig.constrain_axis(3000, -1000, 1000, 0.25, 400), pull,
		"an input further out was let through")

# --- the frame map -------------------------------------------------------------------

func test_the_frame_map_round_trips() -> void:
	for yaw in [0.0, 0.7, -2.0, 3.0]:
		var units: int = UE.yaw_units(yaw)
		assert_almost_eq(wrapf(UE.godot_yaw(units) - yaw, -PI, PI), 0.0, 0.001)
		var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
		assert_eq(UE.dir_yaw(facing), units, "Rotator(Vector(R)).Yaw is not R")

# --- the hand-plant search ------------------------------------------------------------

## [ME:CONFIRMED emulated N4 §3.2] 2: a top inside the box's height; 1: a wall
## with no top in it; 0: nothing.
func test_find_ledge_ex_tells_a_ledge_from_a_wall() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 1.5, 1.0), Vector3(0.0, 0.75, -2.0))
	await step(1)
	var extent := Vector3(0.05, 0.8, 0.05)
	var start := Vector3(0.0, 1.2, 0.0)
	var ledge: Dictionary = player.traces.find_ledge_ex(start, start + Vector3(0.0, 0.0, -2.0), extent)
	assert_eq(ledge["result"], MoveTraces.LEDGE_TOP, "no ledge on a 1.5 m block")
	assert_almost_eq((ledge["ledge_location"] as Vector3).y, 1.5, 0.01, "the top is not the block's")
	var high: Dictionary = player.traces.find_ledge_ex(start + Vector3.UP * 2.0,
		start + Vector3(0.0, 2.0, -2.0), extent)
	assert_eq(high["result"], MoveTraces.LEDGE_NONE, "a sweep over the block found it")
	_box(Vector3(4.0, 6.0, 1.0), Vector3(6.0, 3.0, -2.0))
	await step(1)
	var wall: Dictionary = player.traces.find_ledge_ex(start + Vector3.RIGHT * 6.0,
		start + Vector3(6.0, 0.0, -2.0), extent)
	assert_eq(wall["result"], MoveTraces.LEDGE_WALL, "a 6 m wall reads as something else")

## [ME:CONFIRMED emulated N4 §3.4] THE QUIRK: the two side pairs require
## MoveNormal.Z >= 0.98 and <= 0.2 at once, so only the centre pair can ever
## succeed. A wall only the left pair reaches -- where both of that pair's
## boxes do find the same ledge -- is not found.
func test_the_side_pairs_of_the_hand_plant_search_never_pass() -> void:
	var player: Player = await _player()
	_face(player, 0.0)
	# A 1.5 m block whose right end stops 2 cm left of the body's axis.
	_box(Vector3(4.0, 1.5, 1.0), Vector3(-2.02, 0.75, -1.5))
	await step(1)
	var l: Vector3 = player.global_position
	var side := Vector3(-1.0, 0.0, 0.0)
	var extent := Vector3(0.05, 0.8, 0.05)
	var hand: float = MoveTraces.HAND_PLANT_CHECK_HEIGHT - player.default_collision_half_height()
	var off: float = player.collision_radius() - 0.05
	var base: Vector3 = l + side * MoveTraces.HAND_PLANT_SIDE_OFFSET
	var a: Vector3 = base - side * off
	a.y = l.y + hand
	var b: Vector3 = base + side * off
	b.y = a.y
	var forward := Vector3(0.0, 0.0, -MoveTraces.HAND_PLANT_CHECK_DISTANCE)
	assert_eq(player.traces.find_ledge_ex(a, a + forward, extent)["result"], MoveTraces.LEDGE_TOP,
		"test setup: the left pair's first box finds no ledge")
	assert_eq(player.traces.find_ledge_ex(b, b + forward, extent)["result"], MoveTraces.LEDGE_TOP,
		"test setup: the left pair's second box finds no ledge")
	var found: Dictionary = player.traces.find_auto_move_ledge(l, player.facing(),
		MoveTraces.HAND_PLANT_CHECK_DISTANCE, true, false)
	assert_eq(found["result"], MoveTraces.LEDGE_NONE, "a side pair found a ledge")

# --- the wall run ---------------------------------------------------------------------

## A body on a 3 m platform beside a long, tall wall on its LEFT (face at
## x = -0.6, normal +X), facing 30 degrees into it, the ground far below.
func _wall_run_course() -> Player:
	var player: Player = await _player()
	_box(Vector3(1.0, 1.0, 2.0), Vector3(-0.05, 2.5, 0.0))
	_box(Vector3(1.0, 8.0, 60.0), Vector3(-1.1, 4.0, -28.0))
	player.global_position = Vector3(0.0, 3.05 + player.collision_half_height(), 0.0)
	_face(player, deg_to_rad(30.0))
	await step(10)
	return player

func _run_up(player: Player) -> void:
	player.velocity = player.facing() * 6.0

## [ME:CONFIRMED emulated N3 §2.2] FindWallForward: the pawn facing within 57
## degrees of the wall plane, the wall on its left.
func test_find_wall_forward_finds_the_left_wall() -> void:
	var player: Player = await _wall_run_course()
	_run_up(player)
	var wall_run: WallRunMove = player.move_manager.move_for(Move.WALL_RUN)
	var found: Array = wall_run.find_wall_forward()
	assert_eq(found[0], WallRunMove.SIDE_LEFT, "no left wall found")
	assert_almost_eq((found[1]["move_normal"] as Vector3).x, 1.0, 0.01, "the wall's normal")

## [ME:CONFIRMED decompile N4 §4] The ledge ban's two wall-run consumers
## disagree on purpose: FindWallForward refuses the wall jumped off,
## FindWallSide the wall FACING it -- and lets the one jumped off through.
func test_the_ledge_ban_refuses_opposite_walls_forward_and_sideways() -> void:
	var player: Player = await _wall_run_course()
	_run_up(player)
	var wall_run: WallRunMove = player.move_manager.move_for(Move.WALL_RUN)
	player.illegal_ledge_timer = 2.0
	player.illegal_ledge_normal = Vector3(1.0, 0.0, 0.0)
	assert_eq(wall_run.find_wall_forward()[0], WallRunMove.SIDE_NONE,
		"a forward run onto the wall just left")
	assert_false(wall_run.find_wall_side(WallRunMove.SIDE_LEFT).is_empty(),
		"the side probe refused the wall just left")
	player.illegal_ledge_normal = Vector3(-1.0, 0.0, 0.0)
	assert_true(wall_run.find_wall_side(WallRunMove.SIDE_LEFT).is_empty(),
		"the side probe took a wall facing the one just left")
	player.illegal_ledge_timer = 0.0
	assert_eq(wall_run.find_wall_forward()[0], WallRunMove.SIDE_LEFT, "the ban outlived its timer")

## [ME:CONFIRMED emulated N3 §2.5, 15.10] A jump beside the wall becomes a run
## on its first frame (WallRun is asked before the hand-plant search, and the
## delay gates only the search). Rising, the run takes the vertical speed
## sqrt(2 x 170 uu x 820) and then 820 / 500 uu/s^2 of gravity by the sign of
## Vz; it ends on the frame that starts below -500 uu/s -- 1.65 s at 60 Hz.
func test_a_wall_run_lasts_its_vertical_arc() -> void:
	var player: Player = await _wall_run_course()
	var jump: JumpMove = player.move_manager.move_for(Move.JUMP)
	jump.delay_time_check_auto_moves = 100.0
	var input: ScriptedInputSource = _world["input"]
	_run_up(player)
	# A value no search writes: CheckAutoMoves clears MoveLedgeResult only
	# AFTER the wall run has been asked.
	player.move_ledge_result = 7
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, "the jump did not become a run")
	assert_eq(player.move_ledge_result, 7, "the hand-plant search ran before the wall run")
	var c: WallRunConfig = player.config.wall_run
	var vz: float = sqrt(2.0 * c.wall_running_horisontal_initial_z_height * c.wall_running_horisontal_acceleration)
	var expected := 0
	while vz >= c.wall_running_velocity_stop_limit:
		vz -= (c.wall_running_horisontal_deceleration if vz <= 0.0 else c.wall_running_horisontal_acceleration) * DT
		expected += 1
	var frames := 0
	var parallel := true
	for i in 200:
		await step(1)
		frames += 1
		if player.move_manager.current_name != Move.WALL_RUN:
			break
		if player.is_wall_walking:
			var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
			parallel = parallel and absf(flat.normalized().dot(player.floor_normal)) < 0.01
	assert_eq(player.move_manager.current_name, Move.FALLING, "the run did not end in a fall")
	assert_true(absi(frames - expected) <= 1, "the run lasted %d frames, the arc %d" % [frames, expected])
	assert_true(parallel, "the velocity was not snapped onto the wall")

## [ME:CONFIRMED decompile 15.5] The jump off the run, with the camera turned
## 30 degrees INTO the wall: p = -0.5, which the original does not clamp, so
## the push points into the wall (120 - 200 uu/s) and 1.45 of the along-wall
## speed is kept. Vz = 2 g sqrt(h / g) with h = 100 - 30 uu, g the script's 8.
func test_a_wall_run_jump_does_not_clamp_p() -> void:
	var player: Player = await _wall_run_course()
	var input: ScriptedInputSource = _world["input"]
	_run_up(player)
	input.press_jump()
	await step(1)
	input.release_jump()
	# Jump on the first frame on the wall: ConstrainAxis is pulling the view
	# out of the wall from the run's start, and p must still be negative.
	for i in 20:
		await step(1)
		if player.is_wall_walking:
			break
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, "test setup: not running")
	assert_true(player.is_wall_walking, "test setup: the wall was never reached")
	var floor: Vector3 = player.floor_normal
	var v: Vector3 = player.velocity
	var along: Vector3 = v - floor * v.dot(floor)
	along.y = 0.0
	var launched: Array = []
	var view_yaw: Array = []
	player.move_manager.move_changed.connect(func(_from: StringName, to: StringName) -> void:
		if to == Move.WALLRUN_JUMP:
			launched.append(player.velocity)
			view_yaw.append(player.rotation.y))
	input.press_jump()
	await step(1)
	assert_eq(launched.size(), 1, "no wall-run jump")
	var camera := Vector3(-sin(view_yaw[0]), 0.0, -cos(view_yaw[0]))
	var p: float = Vector3(floor.x, 0.0, floor.z).normalized().dot(camera)
	var c: WallrunJumpConfig = player.config.wallrun_jump
	var out: Vector3 = launched[0]
	assert_lt(p, 0.0, "test setup: the camera is not turned into the wall")
	assert_almost_eq(out.dot(floor), c.wall_running_push_away_speed_noob \
		+ c.wall_running_push_away_speed_pro_add * p, 0.01, "the push off the wall")
	var keep: float = c.wall_running_push_forward_speed_min + (1.0 - c.wall_running_push_forward_speed_min) * (1.0 - p)
	var out_along: Vector3 = out - floor * out.dot(floor)
	out_along.y = 0.0
	assert_almost_eq(out_along.length(), along.length() * keep, 0.01, "the along-wall speed kept")
	var height: float = c.wall_running_jump_off_z_height_forward + p * c.wall_running_jump_off_z_height_max_add_turned
	var g: float = absf(player.gravity_z())
	assert_almost_eq(out.y, g * 2.0 * sqrt(height / g), 0.001, "the jump's vertical speed")
	assert_almost_eq(player.illegal_ledge_timer, 2.0 - DT, 0.001, "the ledge ban was not armed")
	assert_almost_eq(player.illegal_ledge_normal.x, floor.x, 0.001)

## [ME:CONFIRMED decompile 15.5] A run straight out of a wall-run jump counts
## up ConsequtiveWallruns, doubles both wall gravities and gets no new rise.
func test_a_chained_run_is_heavier() -> void:
	var player: Player = await _player()
	var manager: MoveManager = player.move_manager
	var wall_run: WallRunMove = manager.move_for(Move.WALL_RUN)
	manager.start(Move.WALLRUN_JUMP)
	wall_run.next_move = WallRunMove.SIDE_LEFT
	wall_run.wall_normal = Vector3(1.0, 0.0, 0.0)
	player.velocity = Vector3(0.0, 3.0, -5.0)
	manager.set_move(Move.WALL_RUN)
	assert_eq(wall_run.consequtive_wallruns, 1)
	var c: WallRunConfig = player.config.wall_run
	assert_almost_eq(wall_run.horisontal_acceleration, 2.0 * c.wall_running_horisontal_acceleration, 0.0001)
	assert_almost_eq(wall_run.horisontal_deceleration, 2.0 * c.wall_running_horisontal_deceleration, 0.0001)
	assert_almost_eq(player.velocity.y, 3.0, 0.0001, "a chained run was given a rise")
	manager.start(Move.FALLING)
	wall_run.next_move = WallRunMove.SIDE_LEFT
	manager.set_move(Move.WALL_RUN)
	assert_eq(wall_run.consequtive_wallruns, 0, "a run not out of a wall-run jump kept the count")

## [ME:CONFIRMED decompile 15.5] The dodge off a run needs the stick pushed
## AWAY from the wall, and pushes sideways off the pawn's facing.
func test_the_wall_run_dodge_jump_goes_away_from_the_wall() -> void:
	var player: Player = await _player()
	var manager: MoveManager = player.move_manager
	var wall_run: WallRunMove = manager.move_for(Move.WALL_RUN)
	var dodge: Move = manager.move_for(Move.WALLRUN_DODGE_JUMP)
	_face(player, 0.0)
	manager.start(Move.FALLING)
	wall_run.next_move = WallRunMove.SIDE_LEFT
	wall_run.wall_normal = Vector3(1.0, 0.0, 0.0)
	manager.set_move(Move.WALL_RUN)
	player.move_action_hint = Move.MAH_LEFT
	assert_false(dodge.can_do_move(), "a dodge into the left wall")
	player.move_action_hint = Move.MAH_RIGHT
	assert_true(dodge.can_do_move(), "no dodge away from the left wall")
	player.velocity = Vector3(0.0, 0.0, -6.0)
	manager.set_move(Move.WALLRUN_DODGE_JUMP)
	var c: WallrunDodgeJumpConfig = player.config.wallrun_dodge_jump
	assert_almost_eq(player.velocity.x, c.jump_add_xy, 0.0001, "not pushed to the right")
	assert_almost_eq(player.velocity.z, -6.0 * c.dodge_jump_inertia_conservation, 0.0001)
	assert_almost_eq(player.velocity.y, c.base_jump_z, 0.0001)

## [ME:CONFIRMED decompile 15.5] The kick off a run with no target: the
## velocity turned 6000 units away from the wall, then x 1.2.
func test_the_wall_run_kick_turns_off_the_wall() -> void:
	var player: Player = await _player()
	var manager: MoveManager = player.move_manager
	var wall_run: WallRunMove = manager.move_for(Move.WALL_RUN)
	_face(player, 0.0)
	manager.start(Move.FALLING)
	wall_run.next_move = WallRunMove.SIDE_LEFT
	wall_run.wall_normal = Vector3(1.0, 0.0, 0.0)
	manager.set_move(Move.WALL_RUN)
	player.velocity = Vector3(0.0, 0.0, -6.0)
	manager.set_move(Move.MELEE_WALLRUN)
	var angle: float = 6000.0 / UE.UNITS_PER_RADIAN
	assert_almost_eq(player.velocity.x, 6.0 * 1.2 * sin(angle), 0.001, "not turned away from the left wall")
	assert_almost_eq(player.velocity.z, -6.0 * 1.2 * cos(angle), 0.001)

# --- the wall climb -------------------------------------------------------------------

## A tall wall straight ahead (face at z = -1.5, normal +Z).
func _climb_course() -> Player:
	var player: Player = await _player()
	_box(Vector3(6.0, 8.0, 1.0), Vector3(0.0, 4.0, -2.0))
	_face(player, 0.0)
	await step(2)
	return player

## [ME:CONFIRMED emulated N3 §3, 15.10] Running at a wall, forward held, a
## jump becomes a climb (WallRun refuses a head-on wall); from the touch the
## climb rises exactly AddOnHeight -- the launch sqrt(4 h g) under the doubled
## velocity change -- and ends in a fall when the rise stops.
func test_a_wall_climb_rises_its_add_on_height() -> void:
	var player: Player = await _climb_course()
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	player.velocity = Vector3(0.0, 0.0, -6.0)
	input.press_jump()
	var climb: WallClimbMove = player.move_manager.move_for(Move.WALL_CLIMB)
	var reached := false
	for i in 30:
		await step(1)
		input.release_jump()
		if climb.has_reached_wall:
			reached = true
			break
	assert_true(reached, "the jump never touched the wall as a climb")
	var launch: float = player.velocity.y
	var start_y: float = player.global_position.y
	var top: float = start_y
	for i in 120:
		await step(1)
		top = maxf(top, player.global_position.y)
		if player.move_manager.current_name != Move.WALL_CLIMB:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING, "the climb did not end in a fall")
	var g: float = player.config.wall_climb.wall_climbing_gravity
	var vz: float = launch
	var rise := 0.0
	while vz >= 0.0:
		var v1: float = vz - g * DT
		vz = 2.0 * v1 - vz
		rise += v1 * DT
	assert_almost_eq(top - start_y, rise, 0.01, "the climb's rise")

func _start_climb(player: Player) -> void:
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	player.velocity = Vector3(0.0, 0.0, -6.0)
	input.press_jump()
	for i in 30:
		await step(1)
		input.release_jump()
		if player.move_manager.current_name == Move.WALL_CLIMB:
			return

## [ME:CONFIRMED decompile 15.5] Q on a climb is WallClimb180TurnJump; a jump
## inside its 0.6 s window pushes straight off the wall at 400 uu/s with the
## speed 2 g sqrt(250 uu / g); the window closing turns the pawn off the wall
## and hands to Falling.
func test_q_on_a_climb_turns_and_jumps_off_the_wall() -> void:
	var player: Player = await _climb_course()
	var input: ScriptedInputSource = _world["input"]
	await _start_climb(player)
	assert_eq(player.move_manager.current_name, Move.WALL_CLIMB, "test setup: no climb")
	var normal: Vector3 = player.floor_normal
	input.press_turn()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALLCLIMB_180_TURN_JUMP, "Q did not turn off the climb")
	var turn: WallClimb180TurnJumpMove = player.move_manager.move_for(Move.WALLCLIMB_180_TURN_JUMP)
	assert_false(turn.checks_grab() or turn.checks_vault_over() or turn.checks_wall_climb(),
		"the turn asks for auto moves")
	await step(5)
	var launched: Array = []
	input.press_jump()
	await step(1)
	input.release_jump()
	launched.append(player.velocity)
	var c: WallClimb180TurnJumpConfig = player.config.wall_climb_180_turn_jump
	var g: float = absf(player.gravity_z())
	assert_true(turn.jumped(), "the jump was refused inside the window")
	# The frame's own falling physics has already integrated once.
	assert_almost_eq(Vector2(launched[0].x, launched[0].z).dot(Vector2(normal.x, normal.z)),
		c.jump_push_away_speed, 0.05, "the push off the wall")
	assert_almost_eq(launched[0].y, g * 2.0 * sqrt(c.jump_off_z_height / g) - 2.0 * g * DT, 0.05,
		"the jump's vertical speed")
	for i in 60:
		await step(1)
		if player.move_manager.current_name != Move.WALLCLIMB_180_TURN_JUMP:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING, "the turn did not end in a fall")
	var off_wall: float = player.facing().dot(Vector3(normal.x, 0.0, normal.z).normalized())
	assert_almost_eq(off_wall, 1.0, 0.01, "the pawn does not face off the wall")

## [ME:CONFIRMED decompile 15.5] The dodge off a climb clears the grab, vault
## and wall-climb switches for 0.5 s.
func test_the_wall_climb_dodge_jump_clears_the_auto_moves_for_half_a_second() -> void:
	var player: Player = await _player()
	var manager: MoveManager = player.move_manager
	manager.start(Move.WALL_CLIMB)
	player.move_action_hint = Move.MAH_RIGHT
	var dodge: Move = manager.move_for(Move.WALLCLIMB_DODGE_JUMP)
	assert_true(dodge.can_do_move(), "no dodge off a climb")
	manager.set_move(Move.WALLCLIMB_DODGE_JUMP)
	assert_false(dodge.checks_grab(), "the grab is still asked")
	assert_false(dodge.checks_wall_climb(), "the wall climb is still asked")
	dodge.tick_move(0.49)
	assert_false(dodge.checks_vault_over(), "the switches came back early")
	dodge.tick_move(0.02)
	assert_true(dodge.checks_grab() and dodge.checks_vault_over() and dodge.checks_wall_climb(),
		"the switches did not come back")

# --- the controller ------------------------------------------------------------------

## [ME:CONFIRMED decompile N4 §5] On a wall the sideways hint needs the stick
## past 0.8, and any hint that is not that or Up is cleared.
func test_player_wall_walking_raises_the_strafe_hint_to_0_8() -> void:
	var player: Player = await _player()
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.5, 0.0)
	input.state.raw_move = Vector2(0.5, 0.0)
	await step(2)
	assert_eq(player.move_action_hint, Move.MAH_RIGHT, "test setup: no hint on the ground")
	player.controller_state = Move.CS_PLAYER_WALL_WALKING
	player.set_input_hint(0.0, 0.5)
	player._wall_walking_input_hint(0.5)
	assert_eq(player.move_action_hint, Move.MAH_NONE, "a 0.5 strafe hinted on a wall")
	player.set_input_hint(0.0, 0.9)
	player._wall_walking_input_hint(0.9)
	assert_eq(player.move_action_hint, Move.MAH_RIGHT, "a 0.9 strafe did not hint on a wall")
	player.controller_state = Move.CS_PLAYER_WALKING
