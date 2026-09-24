extends ParkourTest

# Task 4: LadderMove core. ✅ THE OWNER: pipes and ladders are one mechanic
# with an authored FRONT ("梯子只有一面可以进入") -- entry is a frontal
# 180-degree fan, open to grounded, airborne AND wall-running bodies alike.
# The climb is collision-checked (Task 3's ruling): a floor hit while
# descending IS the bottom, anything else (a ceiling) just refuses to move
# further without ending the move.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _line: InterestLine = null

## Turns the view `degrees` off the rungs. Both halves are needed: LadderConfig
## sets absolute_yaw_constraint, so apply_look() rebuilds the body's yaw every
## tick from the rig's reference plus its running total, and a test that writes
## only rotation.y has it overwritten on the next frame.
func _turn_view(player: Player, degrees: float) -> void:
	player.camera_rig._look_relative_yaw = deg_to_rad(degrees)
	player.rotation.y = player.visual_yaw() + deg_to_rad(degrees)

func after_each() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func _vertical_ladder(at: Vector3, yaw_deg: float = 0.0, length: float = 3.0) -> InterestLine:
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.LADDER
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(Vector3(0.0, length, 0.0))
	line.position = at
	line.rotation.y = deg_to_rad(yaw_deg)
	add_child_autofree(line)
	return line

func test_front_is_the_nodes_minus_z_flattened() -> void:
	var line := _vertical_ladder(Vector3.ZERO, 90.0)
	await step(1)
	# yaw +90: -Z rotates onto -X.
	assert_almost_eq(line.front().x, -1.0, 0.01, "front did not follow the node yaw")
	assert_almost_eq(line.front().y, 0.0, 0.001, "front must be horizontal")
	assert_true(line.is_in_group("interest_lines"), "lines must be discoverable for the snap scan")

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## Walks a standing player onto a fresh 3 m vertical ladder at the world
## origin (front = -Z) and waits for the ground catch to fire.
func _climbing_player() -> Player:
	var player: Player = await _standing_player()
	_line = _vertical_ladder(Vector3.ZERO, 0.0)
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, player.global_position.y, -stand_off)
	# Facing the ladder: entry now requires it in the player's forward 180.
	player.rotation.y = PI
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			break
	assert_eq(player.move_manager.current_name, Move.LADDER, "test setup: never caught the ladder")
	return player

func test_a_front_approach_attaches_and_a_back_one_does_not() -> void:
	var front_move: StringName = await _ground_catch_attempt(true)
	assert_eq(front_move, Move.LADDER, "walking into the front half-space did not attach")
	var back_move: StringName = await _ground_catch_attempt(false)
	assert_ne(back_move, Move.LADDER, "a back-side pass through the same volume caught the ladder")

## Builds a fresh world, drops a 3 m ladder at the origin, and teleports the
## settled player just off its centreline on the front (-Z) or back (+Z)
## side -- close enough to sit inside reach_radius either way. Returns the
## move active a few ticks later and tears the world down again.
func _ground_catch_attempt(front: bool) -> StringName:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	var stand_off: float = player.config.ladder.stand_off
	var z: float = -stand_off if front else stand_off
	player.global_position = Vector3(0.0, player.global_position.y, z)
	# FACING THE LADDER in both cases (front: turn around to +Z; back: the
	# default -Z already points at it), so what separates the two outcomes
	# is purely the ladder's own front half-space -- the player-facing gate
	# has its own tests below.
	player.rotation.y = PI if front else 0.0
	var line := _vertical_ladder(Vector3.ZERO, 0.0)
	await step(10)
	var result: StringName = player.move_manager.current_name
	# Freed HERE, not at test end: left standing, the next attempt's settle
	# puts its player right on this line and catches it before the teleport.
	line.free()
	TestWorld.teardown(world)
	await step(1)
	return result

func test_climbing_moves_along_the_line() -> void:
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	var before: float = player.global_position.y
	input.state.move = Vector2(0.0, 1.0)  # W: climb up
	for i in 20:
		await step(1)
	var after_up: float = player.global_position.y
	assert_gt(after_up, before, "holding W did not raise the body along the ladder")

	input.state.move = Vector2(0.0, -1.0)  # S: climb down
	for i in 20:
		await step(1)
	assert_lt(player.global_position.y, after_up, "holding S did not lower the body along the ladder")

func test_the_floor_ends_a_descent() -> void:
	var player: Player = await _standing_player()
	# ✅ the owner: designers sink a ladder's ends into geometry -- authored
	# from well below the shared floor's own solid mass (bottom at world
	# y=-3, offset 0) up past the player's standing height (offset ~3.95),
	# so a held descent runs the capsule straight into the floor rather than
	# off the bottom of the line into open air.
	_line = _vertical_ladder(Vector3(0.0, -3.0, 0.0), 0.0, 4.0)
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, player.global_position.y, -stand_off)
	player.rotation.y = PI  # facing the ladder: the forward-180 gate
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			break
	assert_eq(player.move_manager.current_name, Move.LADDER, "test setup: never caught the ladder")
	await step(10)  # past the magnet fade

	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, -1.0)  # S: descend
	var min_y: float = player.global_position.y
	var exited := false
	for i in 90:
		await step(1)
		min_y = minf(min_y, player.global_position.y)
		if player.move_manager.current_name != Move.LADDER:
			exited = true
			break
	assert_true(exited, "a held descent never reached the floor")
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"the floor must hand off to Falling, exactly like a normal landing does next tick")
	assert_gt(min_y, -0.1, "the capsule sank through the floor instead of stopping on it")

func test_bottom_end_release_falls_with_nothing_below() -> void:
	# ✅ THE SPEC, §攀爬: "底端 + 仍按 S：松手，正常下落". The DESCENT-INTO-FLOOR
	# case above is a different mechanism entirely -- there the line's own
	# bottom is sunk into solid geometry, and slide_to()'s floor hit is what
	# ends the move. Here the line's bottom sits well ABOVE the shared floor,
	# with open air underneath: nothing for slide_to() to hit, so without its
	# own check the move used to just clamp _offset at 0.0 and hang there
	# forever with S still held.
	var player: Player = await _standing_player()
	_line = _vertical_ladder(Vector3(0.0, 3.0, 0.0), 0.0, 3.0)  # bottom at y=3, floor is at y=0
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, 3.0, -stand_off)  # right at the bottom rung
	player.rotation.y = PI  # facing the ladder: the forward-180 gate
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			break
	assert_eq(player.move_manager.current_name, Move.LADDER, "test setup: never caught the ladder")
	await step(10)  # past the magnet fade
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"test setup: fell off the bottom before S was even held")

	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, -1.0)  # S: held past the bottom, into open air
	var exited := false
	for i in 30:
		await step(1)
		if player.move_manager.current_name != Move.LADDER:
			exited = true
			break
	assert_true(exited, "S held at the bottom with open air below never let go")
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"the bottom-end release must hand off to Falling, not stay pinned on the line")

func test_a_ceiling_stops_the_ascent() -> void:
	var player: Player = await _standing_player()
	_line = _vertical_ladder(Vector3.ZERO, 0.0, 6.0)
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, player.global_position.y, -stand_off)
	player.rotation.y = PI  # facing the ladder: the forward-180 gate
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			break
	assert_eq(player.move_manager.current_name, Move.LADDER, "test setup: never caught the ladder")
	await step(10)  # past the magnet fade

	# A slab straddling the hang point well below the line's own top (6 m),
	# so what stops the climb is demonstrably the ceiling and not merely
	# running out of ladder. Positioned before add_child so it cannot shove
	# an overlapping body on the tick it appears (see tests/test_checkpoints
	# .gd's own note on this).
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.3, 2.0)
	shape.shape = box
	ceiling.add_child(shape)
	ceiling.position = Vector3(0.0, 2.15, -stand_off)  # bottom surface at y=2.0
	get_tree().root.add_child(ceiling)

	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)  # W: climb up, into the ceiling
	for i in 90:
		await step(1)
	var settled_y: float = player.global_position.y
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"the ceiling ended the climb instead of merely refusing to move further")
	for i in 20:
		await step(1)
	assert_almost_eq(player.global_position.y, settled_y, 0.05, \
		"the ceiling did not stop the ascent (%.3f -> %.3f)" % [settled_y, player.global_position.y])
	assert_lt(player.global_position.y, 3.0, "the body climbed past the ceiling instead of being blocked by it")

	ceiling.queue_free()

func test_crouch_lets_go_and_spends_the_roll() -> void:
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "crouch did not let go of the ladder")
	# The same press that let go must not ALSO survive to buy a roll at the
	# landing -- mirrors ZiplineMove's own release (see test_zipline_move.gd's
	# test_the_release_press_does_not_also_buy_a_roll_at_the_landing). Faked a
	# genuine drop the same way: push the fall tracker's baseline up so the
	# short trip back to the floor reads as a real fall, done AFTER the
	# release since LadderMove re-baselines it every tick while still active.
	player.fall_tracker.reset(player.global_position.y + player.config.pawn.skill_roll_landing_height + 0.5)
	var saw_roll := false
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.SKILL_ROLL:
			saw_roll = true
		if player.grounded and player.move_manager.current_name != Move.SKILL_ROLL:
			break
	assert_false(saw_roll, "the same press that released the ladder also fired a skill roll")

func test_wallrun_can_be_caught_by_a_ladder() -> void:
	# ✅ THE OWNER: ME has a level built on wall-running straight into a
	# pipe/ladder -- WallRunMove has to ask the same frontal gate the ground
	# and the air do.
	assert_true(await _wallrun_catches_pipe(0.8), \
		"a wall run passing through a ladder's front volume was not caught")

## A pipe standing further off its wall than the capsule radius: the runner
## passes beside it, a little BEHIND its front plane (LadderConfig.back_slack).
## Stormdrain's pipe on the ring wall sits 0.58 m off it.
func test_wallrun_catches_a_pipe_standing_off_the_wall() -> void:
	assert_true(await _wallrun_catches_pipe(0.45 - 0.58), \
		"a wall run beside a pipe standing off its wall was not caught")

## Wall-runs along a wall whose face is at x = 0.45, with a pipe at `pipe_x`
## a little ahead along the run. Returns whether the pipe was caught.
func _wallrun_catches_pipe(pipe_x: float) -> bool:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(20.0, 6.0, 1.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	# Position before add_child: see test_wall_run_entry.gd's own note on why
	# (an overlapping collider added at the origin shoves the body on the
	# very next physics tick otherwise).
	wall.position = Vector3(0.95, 3.0, 0.0)
	wall.rotation = Vector3(0.0, PI * 0.5, 0.0)
	get_tree().root.add_child(wall)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	assert_eq(player.move_manager.current_name, Move.WALKING, \
		"test setup: player did not settle onto the floor before the wall attach")

	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"test setup: the jump never sent the player airborne")
	# Strafe-style approach along -Z, parallel to the wall's face -- same
	# entry technique test_wall_run_entry.gd's own _attach_to_wall() uses.
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup: the player never attached to the wall")

	# A pipe MOUNTED ON THE WALL, a little ahead along the run: front (-Z
	# rotated by yaw +90 = -X) faces out of the wall toward the runner's
	# side of it, and being ahead keeps it inside the runner's forward 180
	# -- the shape ME's wallrun-into-pipe level actually has. yaw 0 (front
	# aligned WITH the travel) would put the runner behind the pipe's back
	# and rightly never catch.
	_line = _vertical_ladder(Vector3(pipe_x, player.global_position.y - 1.0, \
		player.global_position.z - 1.5), 90.0)
	var caught := false
	for i in 30:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			caught = true
			break

	_line.free()
	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)
	return caught

# --- Catching a ladder out of a fall -------------------------------------------
#
# ✅ THE OWNER measured both halves in the original: a ladder CAN be caught
# while already falling, and a catch that stops a fall past
# hard_landing_height costs the same red-screen lockout a hard landing does
# instead of being refused.

## Jumps a settled player (so nothing grounded can clobber the velocity below
## — WalkingMove pins velocity.y to -floor_snap_speed every tick), then drops
## them onto the front side of a fresh 6 m ladder at a speed far past the
## 6 m/s the ladder config used to refuse a catch at. `fake_fall_height`, when
## positive, buys a fall the test never actually took.
func _fall_onto_ladder(fake_fall_height: float) -> Player:
	var player: Player = await _standing_player()
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_ne(player.move_manager.current_name, Move.WALKING, 		"test setup: the jump never left the ground")
	# Spans y 1..7, so the whole approach happens well clear of the floor.
	_line = _vertical_ladder(Vector3(0.0, 1.0, 0.0), 0.0, 6.0)
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, 5.0, -stand_off)
	player.rotation.y = PI  # facing the ladder
	# A real 5.3 m fall arrives at about 13 m/s (gravity 16), so this is the
	# speed the catch has to survive — twice the old limit over.
	player.velocity = Vector3(0.0, -12.0, 0.0)
	if fake_fall_height > 0.0:
		# The tracker is launch-relative, so raising its baseline is how a test
		# buys height it never fell — the same idiom
		# test_crouch_lets_go_and_spends_the_roll() uses.
		player.fall_tracker.reset(player.global_position.y + fake_fall_height)
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			break
	return player

func test_a_fast_fall_still_catches_the_ladder() -> void:
	var player: Player = await _fall_onto_ladder(0.0)
	assert_eq(player.move_manager.current_name, Move.LADDER, 		"a body falling well past the old fall_limit failed to catch the ladder")

func test_a_hard_catch_locks_the_body_and_then_lets_go() -> void:
	# Comfortably past hard_landing_height (5.3) and short of
	# falling_uncontrolled_height (10), where nothing catches anything.
	var player: Player = await _fall_onto_ladder(6.0)
	assert_eq(player.move_manager.current_name, Move.LADDER, 		"test setup: the hard fall never caught the ladder")
	var input: ScriptedInputSource = _world["input"]
	var ladder := player.move_manager.move_for(Move.LADDER) as LadderMove
	var offset_at_catch: float = ladder.climbing_offset()

	# Half a second in, well inside the lockout: W must buy nothing.
	input.state.move = Vector2(0.0, 1.0)
	await step(30)
	assert_eq(player.move_manager.current_name, Move.LADDER, 		"the lockout let go of the ladder on its own")
	assert_almost_eq(ladder.climbing_offset(), offset_at_catch, 0.001, 		"W climbed the ladder during the hard-catch lockout")
	# ...and neither must crouch. NOT MEASURED — see LadderMove._arm_hard_catch().
	input.press_crouch()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.LADDER, 		"crouch released the grip during the hard-catch lockout")

	# Past the lockout, the ladder is an ordinary ladder again.
	await step(120)
	assert_eq(player.move_manager.current_name, Move.LADDER, 		"test setup: something else took the body before the lockout ran out")
	assert_gt(ladder.climbing_offset(), offset_at_catch, 		"W never started climbing once the lockout let go")
	input.press_crouch()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, 		"crouch did not let go once the lockout had run out")

# --- Task 5: the jump-off chain ------------------------------------------------
#
# ✅ THE OWNER: "AD+空格如果没有其他梯子是不会触发跳的" -- with no directional
# snap target (Task 6; this task's _scan_snap_target() always returns null)
# space only leaves the ladder once the view has turned past
# LadderConfig.jump_angle_deg off the ladder's own facing. Squared to the
# ladder, the press does nothing at all.

func test_space_facing_the_ladder_does_nothing() -> void:
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade, facing squared to the ladder
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"a jump pressed while facing the ladder let go of it anyway")

func test_a_turned_head_jumps_along_the_look() -> void:
	var player: Player = await _climbing_player()
	# Past the magnet fade AND the eye's own scripted-turn catch-up
	# (CameraRig._scripted_yaw_lag, set by the fade-in's absorb_body_yaw()
	# calls): the camera visually trails a scripted turn for a few ticks, so
	# reading it too early would measure that trailing lag as if it were a
	# player-driven turn.
	await step(40)
	_turn_view(player, 60.0)
	player.camera_rig.set_pitch(deg_to_rad(30.0))
	await step(1)  # let the pitch reach the camera transform
	var look: Vector3 = -player.camera_rig.camera.global_transform.basis.z
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"a 60 degree turned head did not jump off the ladder")
	assert_gt(player.velocity.dot(look), 0.0, \
		"the launch did not follow the turned-away look direction")
	var incline := rad_to_deg(atan2(player.velocity.y, Vector2(player.velocity.x, player.velocity.z).length()))
	assert_almost_eq(incline, player.config.ladder.jump_min_pitch_deg, 1.0,
		"a view pitched up 30, under the floor, did not launch at the floor incline")

func test_the_into_wall_component_survives() -> void:
	# 🔒 PROTECTED TECHNIQUE -- spec invariant #1, mirroring GrabMove's own
	# protected test (test_a_bare_turn_throws_you_at_your_own_ledge in
	# test_grab_jump.gd). Turning just past jump_angle_deg and jumping still
	# throws the body partly AT the ladder's own geometry -- that into-the-wall
	# component is the vault-finisher speedrun glitch (grab_move.gd's
	# _launch_direction() carries the owner's full account). DO NOT "fix" this
	# by projecting the component out of the launch; that quietly deletes the
	# technique.
	var player: Player = await _climbing_player()
	await step(40)  # past the magnet fade AND the eye's scripted-turn catch-up
	_turn_view(player, 47.0)  # just past the 45 degree gate
	await step(1)
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"a 47 degree turned head did not jump off the ladder")
	assert_gt(player.velocity.dot(-_line.front()), 0.0, \
		"the launch lost the into-the-wall component the vault finisher depends on")

func test_a_lip_at_the_top_catches_the_into_wall_jump() -> void:
	# 🔒 PROTECTED TECHNIQUE -- spec invariant #2: near the top, a camera
	# turned past jump_angle_deg and space pressed must have the airborne
	# probes (GrabMove's/SpeedVaultMove's own, wholly unaware this body just
	# left a ladder) actually CATCH the lip the into-wall component throws
	# the body at. Invariant #1 above pins the launch DIRECTION; this pins
	# that the direction is actually good for something -- a real ledge
	# planted where that component points must not be sailed past into an
	# ordinary fall.
	var player: Player = await _climbing_player()
	var input: ScriptedInputSource = _world["input"]
	var ladder_move := player.move_manager.move_for(Move.LADDER) as LadderMove
	# Climb close to the top WITHOUT reaching it -- reaching it (Task 7)
	# would exercise the top-exit's own space-beats-carry gate (invariant #3,
	# test_space_beats_the_top_exit above) instead of this one.
	input.state.move = Vector2(0.0, 1.0)  # W
	for i in 200:
		await step(1)
		if ladder_move.climbing_offset() >= 2.5:
			break
	input.state.move = Vector2.ZERO
	await step(3)  # let the climb settle at this offset
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"test setup: left the ladder before reaching the fixture height")
	assert_gt(ladder_move.climbing_offset(), 2.0, "test setup: never got near the top")

	_turn_view(player, 50.0)  # past jump_angle_deg (45)
	var new_yaw: float = player.rotation.y
	await step(1)  # let the turn reach the camera transform

	# A WALL, not a thin lip: tall enough that its face still blocks
	# Probes.vault_query()'s own hand-reach sample (1.89 m above the feet,
	# SpeedVaultConfig.max_edge_above_feet) -- which is what routes this
	# catch through the grab probe rather than the vault one, sidestepping
	# vault_query()'s speed_z gate entirely (a bare horizontal jump reads as
	# falling, not rising, one tick after launch, once gravity has clipped
	# it -- see AirborneMove._vault_speed_z()). Its TOP sits within
	# GrabConfig's own reachable band (min_wall_height 1.8 .. ledge_max_height
	# 2.8 above the feet) so ledge_query() finds a graspable top there
	# instead. Its face sits within IntoGrabConfig.max_reach_distance (0.8 m)
	# of the launch point, well inside the single physics tick this jump
	# covers before FallingMove's own probe_transition() first runs.
	var forward_dir: Vector3 = Vector3(-sin(new_yaw), 0.0, -cos(new_yaw))
	var feet_y: float = player.global_position.y - player.standing_height() * 0.5
	var near_face_distance: float = 0.7
	var depth: float = 1.0
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(3.0, 3.0, depth)  # top at feet+2.0, bottom at feet-1.0
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.rotation.y = new_yaw  # own -Z aligned with forward_dir, matching the probes' own aim
	get_tree().root.add_child(wall)  # BEFORE global_position: it needs to be in the tree first
	var centre_xz: Vector3 = player.global_position \
		+ forward_dir * (near_face_distance + depth * 0.5)
	wall.global_position = Vector3(centre_xz.x, feet_y + 0.5, centre_xz.z)
	await step(1)  # let the new collider register before anything probes it

	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"a 50 degree turned jump near the top did not leave the ladder")

	var caught := false
	for i in 20:
		await step(1)
		var name: StringName = player.move_manager.current_name
		if name == Move.SPEED_VAULT or name == Move.INTO_GRAB or name == Move.GRAB:
			caught = true
			break
		if name != Move.FALLING:
			break  # left Falling for something that is not a catch: a real miss
	assert_true(caught, \
		"the into-wall jump sailed past the lip into an ordinary fall instead of being caught")

	wall.queue_free()

# --- Task 6: 快捷吸附 (assisted hop) --------------------------------------------
#
# ✅ THE OWNER: no aiming needed -- the scan and the launch both live entirely
# in the LADDER's own frame (front x up), with no camera read anywhere.
#
# Geometry shared by the two hop tests below: _climbing_player() attaches to a
# 3 m ladder at the world origin, front = -Z (see its own docstring), standing
# at roughly x=0, z=-stand_off, FACING +Z (enter()'s own note: the body faces
# -front). For any facing direction, left = UP.cross(facing) -- so facing
# +Z, the climber's LEFT is UP.cross((0,0,1)) = (0,1,0) x (0,0,1) =
# (1*1-0*0, 0*0-0*1, 0*0-1*0) = (1,0,0) = +X (right is the negation, -X).
# A second ladder sits 2.5 m along +X -- the primary's LEFT, matching
# _scan_snap_target's (fixed) dir formula, which puts side -1 (A) at +X here
# -- built the same length, at the same world y, so the two lines' climbable
# ranges line up and the height component of the scan's cone check stays
# small. Its yaw (+90 degrees) points ITS OWN front at -X, i.e. back toward
# the primary ladder: the body flies in from the -X side, so that is exactly
# the side the arrival catch's frontal gate (front_side_allows) needs it
# approaching from.

func test_a_side_hop_snaps_to_the_neighbour_ladder() -> void:
	var player: Player = await _climbing_player()
	var neighbour := _vertical_ladder(Vector3(2.5, 0.0, 0.0), 90.0)
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(-1.0, 0.0)  # A: left, toward the neighbour
	input.press_jump()
	await step(1)
	# The flight is ballistic, not driven -- no further steering while airborne.
	input.state.move = Vector2.ZERO
	var caught := false
	for i in 120:  # ~2 s of stepped ticks
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			caught = true
			break
	assert_true(caught, "the side-hop never re-attached to the neighbour ladder")
	assert_almost_eq(player.global_position.x, neighbour.position.x, 1.0, \
		"the caught body did not land near the neighbour ladder")

func test_no_neighbour_means_no_hop() -> void:
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	var before: Vector3 = player.global_position
	input.state.move = Vector2(-1.0, 0.0)  # A: left, nothing out there
	input.press_jump()
	await step(1)
	input.state.move = Vector2.ZERO
	await step(5)
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"a hop with no neighbour in range let go of the ladder anyway")
	assert_almost_eq(player.global_position.x, before.x, 0.05, \
		"a hop with no neighbour in range moved the body")

func test_the_scan_respects_direction() -> void:
	var player: Player = await _climbing_player()
	_vertical_ladder(Vector3(2.5, 0.0, 0.0), 90.0)  # neighbour on the LEFT (+X)
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	var before: Vector3 = player.global_position
	input.state.move = Vector2(1.0, 0.0)  # D: right (-X), away from the neighbour
	input.press_jump()
	await step(1)
	input.state.move = Vector2.ZERO
	await step(5)
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"D+space hopped toward a neighbour that was on the LEFT")
	assert_almost_eq(player.global_position.x, before.x, 0.05, \
		"the refused hop still moved the body")

func test_plain_space_with_no_direction_held_does_not_scan() -> void:
	# ✅ THE SPEC: the assisted-hop scan only runs while a direction is
	# actually "按着" (held) -- plain space facing the ladder, nothing else
	# down, is 无操作. THE LATENT BUG THIS PINS: side defaulted to 0 for "no
	# A/D held", and _scan_snap_target(0) reads side 0 as "scan straight
	# back" -- so a bare space press used to run that scan anyway, with no
	# direction requested at all.
	#
	# The neighbour below sits exactly where that straight-back scan would
	# have looked (dir = _line.front(), i.e. -Z, "behind" the climber who
	# faces +Z -- see enter()'s own note), yawed so it WOULD have caught the
	# hop if the scan had fired: this is not a miss-by-distance-or-cone case,
	# it is the scan never running at all.
	var player: Player = await _climbing_player()
	var stand_off: float = player.config.ladder.stand_off
	_vertical_ladder(Vector3(0.0, 0.0, -stand_off - 3.0), 180.0)  # 3 m behind the climber's back
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	var before: Vector3 = player.global_position
	input.state.move = Vector2.ZERO  # no A, no D, no S -- 无操作
	input.press_jump()
	await step(1)
	input.state.move = Vector2.ZERO
	await step(5)
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"a direction-less space hopped to the ladder behind the climber's back")
	assert_almost_eq(player.global_position.x, before.x, 0.05, \
		"a direction-less space moved the body toward the back-scan target")
	assert_almost_eq(player.global_position.z, before.z, 0.05, \
		"a direction-less space moved the body toward the back-scan target")

# --- Task 7: the top exit --------------------------------------------------
#
# ✅ THE OWNER: the top of the line plays out the same as ClimbUp -- probe for
# a standable deck behind the top and, if there is one, carry the body onto it
# on a fixed clock; otherwise W simply does nothing there. Geometry shared by
# the two deck tests below: _climbing_player()'s 3 m ladder at the world
# origin, front = -Z, so the deck behind the top (+Z, top_exit_reach along
# -front()) sits at world (0, 3, top_exit_reach).

## Builds a flat platform whose top surface sits at `top_y`, offset
## `top_exit_reach` behind the ladder's own top along +Z -- exactly where
## LadderMove._probe_top_deck()'s candidate lands.
##
## SHALLOW IN Z AND PULLED CLEAR OF THE CLIMB, on purpose: the climbing
## capsule itself rides at z = -stand_off (0.4 m radius, so it sweeps out to
## z = 0.0), and a deck reaching back to the ladder's own face would clip that
## sweep well before the body ever reaches the top -- caught by hand: an
## earlier version spanning the full top_exit_reach depth stalled the climb
## at world y ~= 1.1 (half_height=0.95 above the capsule origin already
## grazing the deck's underside at y=2.0). Starting the near face at
## reach - 0.8 keeps it a clear 0.4 m past the climb's own reach.
func _top_deck(player: Player, top_y: float) -> StaticBody3D:
	var reach: float = player.config.ladder.top_exit_reach
	var deck := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.0, 1.6)
	shape.shape = box
	deck.add_child(shape)
	deck.position = Vector3(0.0, top_y - 0.5, reach)
	get_tree().root.add_child(deck)
	return deck

func test_top_plus_w_carries_the_body_onto_the_deck() -> void:
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade

	var reach: float = player.config.ladder.top_exit_reach
	var deck_y: float = _line.length()
	var deck := _top_deck(player, deck_y)
	await step(1)  # let the new collider register before anything probes it

	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)  # W: climb, then carry over the top
	var start_z: float = player.global_position.z
	var landing_y: float = deck_y + player.standing_height() * 0.5

	var saw_carry := false
	var mid_pos: Vector3 = Vector3.ZERO
	var exited := false
	var climb_ticks: int = int(4.0 / player.config.ladder.climb_speed * Engine.physics_ticks_per_second)
	var carry_ticks: int = int(player.config.ladder.top_exit_time * Engine.physics_ticks_per_second)
	for i in (climb_ticks + carry_ticks + 30):
		await step(1)
		if exited:
			continue
		if player.move_manager.current_name == Move.LADDER and not saw_carry \
				and player.global_position.z > start_z + 0.3 \
				and player.global_position.z < reach - 0.2:
			# Mid-phase: strictly between where the climb left off and the
			# deck the probe found -- never teleported.
			mid_pos = player.global_position
			saw_carry = true
		if player.move_manager.current_name != Move.LADDER:
			exited = true
			input.state.move = Vector2.ZERO  # stop steering once carried off
	await step(5)  # let WalkingMove's own floor-snap tick verify the landing

	assert_true(saw_carry, "never observed the carry running mid-flight")
	assert_gt(mid_pos.z, start_z, "the mid-phase sample never left the ladder's own line")
	assert_lt(mid_pos.z, reach, "the mid-phase sample was already at the deck")

	assert_eq(player.move_manager.current_name, Move.WALKING, \
		"the top exit did not hand off to ordinary ground movement")
	assert_true(player.grounded, "the carry did not end grounded on the deck")
	assert_almost_eq(player.global_position.y, landing_y, 0.15, \
		"the body did not settle at standing height above the deck")
	# NEAREST standable point wins (the near-to-far scan): the landing hugs
	# the lip instead of sitting a full top_exit_reach back -- ✅ the owner's
	# red curve. The deck's near edge is what bounds it, not `reach`.
	assert_lt(player.global_position.z, reach, \
		"the landing sat all the way back at the far candidate")
	assert_gt(player.global_position.z, 0.2, \
		"the landing failed to make it past the lip at all")

	deck.queue_free()

func test_a_ladder_standing_proud_of_its_deck_still_lets_you_off() -> void:
	# Many of the original's ladders run on past the deck they serve, rails
	# and all, the way a real one does. The top of the line is then well above
	# the deck, and a probe that only looked half a metre down refused them.
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var deck := _top_deck(player, _line.length() - 1.2)
	await step(1)
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)
	var climb_ticks: int = int(4.0 / player.config.ladder.climb_speed * Engine.physics_ticks_per_second)
	var carry_ticks: int = int(player.config.ladder.top_exit_time * Engine.physics_ticks_per_second)
	var exited := false
	for i in (climb_ticks + carry_ticks + 30):
		await step(1)
		if player.move_manager.current_name != Move.LADDER:
			exited = true
			input.state.move = Vector2.ZERO
			break
	assert_true(exited, "a ladder rising 1.2 m past its deck could not be left at the top")
	deck.queue_free()

func test_no_deck_means_no_exit() -> void:
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)  # W: climb to the top and keep holding
	var climb_ticks: int = int(4.0 / player.config.ladder.climb_speed * Engine.physics_ticks_per_second)
	for i in climb_ticks:
		await step(1)
	# Nothing stands behind the top -- give the (absent) exit every chance to
	# fire before checking it never did.
	var settle_ticks: int = int(player.config.ladder.top_exit_time * Engine.physics_ticks_per_second) + 30
	for i in settle_ticks:
		await step(1)
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"W with nothing standable behind the top still left the ladder")
	var ladder_move := player.move_manager.move_for(Move.LADDER) as LadderMove
	assert_almost_eq(ladder_move.climbing_offset(), _line.length(), 0.05, \
		"the offset did not stay capped at the line's own top")
	# The line's top is the HANDS' highest grip (LadderConfig.hand_height),
	# so the capsule centre caps a hand's height below it -- ✅ the owner:
	# "顶端点应该是手可以碰到的最高点，而不是胶囊中心."
	assert_almost_eq(player.global_position.y,
		_line.length() - player.config.ladder.hand_height, 0.1, \
		"the body's centre did not cap a hand-height below the line top")

func test_space_beats_the_top_exit() -> void:
	# 🔒 PROTECTED TECHNIQUE -- spec invariant #3: at the very top, a jump
	# past jump_angle_deg still fires the ordinary jump-off chain (Task 5)
	# instead of the scripted top exit, EVEN WHEN a valid deck is in reach and
	# W is held on the very same tick. The jump chain sits ahead of the
	# top-exit check in physics_update() on purpose (see that function's own
	# comment on the ordering) -- DO NOT "fix" this by moving the top-exit
	# check earlier; that would make the carry preempt space exactly where
	# the owner said space must still win.
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var input: ScriptedInputSource = _world["input"]

	# Reach the very top first, with nothing behind it yet -- so setting the
	# scene up cannot itself trigger the carry.
	input.state.move = Vector2(0.0, 1.0)  # W
	var climb_ticks: int = int(4.0 / player.config.ladder.climb_speed * Engine.physics_ticks_per_second)
	for i in climb_ticks:
		await step(1)
	var ladder_move := player.move_manager.move_for(Move.LADDER) as LadderMove
	assert_almost_eq(ladder_move.climbing_offset(), _line.length(), 0.05, \
		"test setup: never reached the top of the line")

	# A deck now appears behind the top. W is released FIRST, so the
	# collider settling into the physics world cannot fire the carry on its
	# own before the jump is even pressed.
	input.state.move = Vector2.ZERO
	var deck := _top_deck(player, _line.length())
	await step(5)
	assert_eq(player.move_manager.current_name, Move.LADDER, \
		"test setup: the body left the ladder before the jump was even pressed")

	# NOW: at the very top, a valid deck in reach, camera turned past
	# jump_angle_deg, W and jump pressed together on the same tick.
	_turn_view(player, 50.0)
	await step(1)
	input.state.move = Vector2(0.0, 1.0)  # W held again
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"a turned-away jump at the very top ran the scripted top exit instead of the jump chain")

	deck.queue_free()

func test_a_release_inside_the_volume_never_regrabs_by_itself() -> void:
	# ✅ THE OWNER: "离开后如果不退出它的检测范围再重新进入则不要自动爬" --
	# crouch off at the foot, stand there past the cooldown: the ladder must
	# NOT take the body back until it leaves the volume and returns.
	var player: Player = await _climbing_player()
	await step(10)  # past the magnet fade
	var line: InterestLine = _line
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(3)
	assert_ne(player.move_manager.current_name, Move.LADDER,
		"test setup: crouch did not release")
	# Well past same_line_redo_time, landed at the foot, still inside the
	# volume the whole time.
	await step(int(player.config.ladder.same_line_redo_time * 60.0) + 30)
	assert_ne(player.move_manager.current_name, Move.LADDER,
		"the ladder took the body back while it never left the volume")
	assert_false(player.line_ready(line),
		"the line reported ready while the body never left its volume")

func test_pushing_at_the_latched_ladder_takes_it_back() -> void:
	# ✅ THE OWNER, on the original: after the cooldown, "有朝向梯子的水平速度
	# （比如对着它按W）还是会重新进入的" -- the rule the shift-drop-then-W
	# save-yourself glitch is built on. Passive standing stays released
	# (previous test); active pushing re-grabs.
	var player: Player = await _climbing_player()
	await step(10)
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(3)
	assert_ne(player.move_manager.current_name, Move.LADDER,
		"test setup: crouch did not release")
	await step(int(player.config.ladder.same_line_redo_time * 60.0) + 10)
	assert_ne(player.move_manager.current_name, Move.LADDER,
		"test setup: re-grabbed with no input at all")
	# The body faces the ladder (freeze kept it squared); W pushes toward it.
	input.state.move = Vector2(0.0, 1.0)
	var regrabbed := false
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			regrabbed = true
			break
	input.state.move = Vector2.ZERO
	assert_true(regrabbed, "W at the latched ladder never took it back")

func test_backing_in_spends_the_chance_and_turning_does_not_refund_it() -> void:
	# ✅ THE OWNER: entry needs the ladder in the view's forward 180 -- and a
	# first FAILED check is spent: "背着进入梯子的检测范围，然后再转过身，
	# 应该不会自动进入梯子." Walking back toward it is what re-arms.
	var player: Player = await _standing_player()
	# Ladder BEHIND the default -Z facing: the player backs into the volume.
	# yaw 0 keeps its front (-Z) pointing AT the player -- the front-side
	# gate passes and what fails is purely the player's own forward-180.
	var line := _vertical_ladder(Vector3(0.0, 0.0, player.global_position.z + 0.4), 0.0)
	await step(10)
	assert_ne(player.move_manager.current_name, Move.LADDER,
		"a ladder behind the view caught the body anyway")
	# Turning in place: the chance is already spent, nothing may fire.
	player.rotation.y = PI
	await step(30)
	assert_ne(player.move_manager.current_name, Move.LADDER,
		"turning around inside the volume auto-entered the ladder")
	# Meaning it: push toward the rungs.
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)
	var caught := false
	for i in 60:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			caught = true
			break
	input.state.move = Vector2.ZERO
	assert_true(caught, "walking toward the latched ladder never re-armed the catch")

# --- the climb's look assist ------------------------------------------------

func test_a_view_turned_past_the_assist_angle_refuses_the_climb() -> void:
	# The pair with the test below: past climb_assist_angle_deg a held W is
	# read as lining up a jump off, and the body stays where it is.
	var player: Player = await _climbing_player()
	await step(40)  # past the magnet fade and the eye's catch-up
	var ladder_move := player.move_manager.move_for(Move.LADDER) as LadderMove
	_turn_view(player, player.config.ladder.climb_assist_angle_deg + 20.0)
	await step(1)
	var before: float = ladder_move.climbing_offset()
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)  # W
	await step(20)
	assert_almost_eq(ladder_move.climbing_offset(), before, 0.001, \
		"W climbed with the view turned past the assist angle")

func test_a_climb_inside_the_assist_angle_walks_the_view_back() -> void:
	var player: Player = await _climbing_player()
	await step(40)
	var ladder_move := player.move_manager.move_for(Move.LADDER) as LadderMove
	_turn_view(player, player.config.ladder.climb_assist_angle_deg - 10.0)
	await step(1)
	var before: float = ladder_move.climbing_offset()
	var input: ScriptedInputSource = _world["input"]
	input.state.move = Vector2(0.0, 1.0)  # W
	await step(60)
	assert_gt(ladder_move.climbing_offset(), before, \
		"W inside the assist angle did not climb")
	var turned: float = absf(float(player.camera_rig.look_debug()["relative_yaw"]))
	assert_lte(turned, deg_to_rad(player.config.ladder.climb_look_yaw_deg) + 0.01, \
		"a held climb left the view outside the climb fan")
