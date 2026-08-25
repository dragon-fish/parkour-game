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
	var line := _vertical_ladder(Vector3.ZERO, 0.0)
	await step(10)
	var result: StringName = player.move_manager.current_name
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

func test_a_ceiling_stops_the_ascent() -> void:
	var player: Player = await _standing_player()
	_line = _vertical_ladder(Vector3.ZERO, 0.0, 6.0)
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, player.global_position.y, -stand_off)
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

	# A ladder's front volume, planted a little ahead of the body along its
	# direction of travel (-Z) so the ongoing run carries it across the
	# front-side boundary over the next few ticks, exactly like meeting one
	# mid-run would.
	_line = _vertical_ladder(Vector3(player.global_position.x, player.global_position.y - 1.0, \
		player.global_position.z - 0.3), 0.0)
	var caught := false
	for i in 30:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			caught = true
			break
	assert_true(caught, "a wall run passing through a ladder's front volume was not caught")

	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)

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
	var facing_yaw: float = player.rotation.y
	player.rotation.y = facing_yaw + deg_to_rad(60.0)
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
	assert_gt(player.velocity.y, 0.0, "looking up did not send the launch up")

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
	var facing_yaw: float = player.rotation.y
	player.rotation.y = facing_yaw + deg_to_rad(47.0)  # just past the 45 degree gate
	await step(1)
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"a 47 degree turned head did not jump off the ladder")
	assert_gt(player.velocity.dot(-_line.front()), 0.0, \
		"the launch lost the into-the-wall component the vault finisher depends on")
