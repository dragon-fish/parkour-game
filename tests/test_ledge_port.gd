extends ParkourTest

# The ledge family as ported from the original: vaults, the grab and its
# moves, ladders, ledge walks and balance beams. [ME:CONFIRMED decompile
# script TdMove_*.uc, N4, N5] Structural invariants, the original's formulas
# in closed form and the quirks kept -- no tuning values.

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
	body.position = center
	get_tree().root.add_child(body)
	_extra.append(body)
	return body

func _face(player: Player, yaw: float) -> void:
	player.rotation.y = yaw
	player.pawn_yaw = yaw

func _line(kind: InterestLine.Kind, a: Vector3, b: Vector3, front_yaw: float = 0.0) -> InterestLine:
	var line := InterestLine.new()
	line.kind = kind
	# The points are given in the world: the curve holds them in the line's frame.
	var to_local := Basis(Vector3.UP, -front_yaw)
	var curve := Curve3D.new()
	curve.add_point(to_local * a)
	curve.add_point(to_local * b)
	line.curve = curve
	line.rotation.y = front_yaw
	get_tree().root.add_child(line)
	_extra.append(line)
	return line

## Hangs the body from the top edge of a wall facing +Z at z = `face_z`, the
## top at `top`: the hand-plant data, then IntoGrab's catch.
func _hang(player: Player, top: float, face_z: float, x: float = 0.0) -> GrabMove:
	_face(player, 0.0)
	player.move_ledge_location = Vector3(x, top, face_z)
	player.move_ledge_normal = Vector3.UP
	player.move_normal = Vector3(0.0, 0.0, 1.0)
	var into: IntoGrabMove = player.move_manager.move_for(Move.INTO_GRAB)
	player.global_position = into._hang_point()
	player.velocity = Vector3.ZERO
	player.move_manager.set_move(Move.INTO_GRAB)
	into.reached_precise_location()
	return player.move_manager.move_for(Move.GRAB)

# --- the vaults -----------------------------------------------------------------------

## [ME:CONFIRMED decompile, script_raw checked] AutoStepUp's CanDoMove returns
## false straight after TdMove's checks: the move is dead.
func test_auto_step_up_never_starts() -> void:
	var player: Player = await _player()
	player.found_ledge = true
	player.move_action_hint = Move.MAH_UP
	assert_false(player.move_manager.can_do(Move.AUTO_STEP_UP), "AutoStepUp agreed to start")

## [ME:CONFIRMED decompile] The row loop lets row 0 (autostepuprightleg)
## through whatever the onto plan says; every other row must match it. And a
## vault asked from a hang (a transfer up) always takes row 3, vaultOver.
func test_the_vault_rows_skip_the_onto_test_for_row_zero_only() -> void:
	var player: Player = await _player()
	var vault: SpeedVaultMove = player.move_manager.move_for(Move.VAULT_OVER)
	player.velocity = Vector3(0.0, -1.0, -2.0)
	vault.handplant_height = 0.4
	vault.vault_onto = false
	assert_eq(vault.update_active_vault_type(0.1), 0, "row 0 refused an over plan")
	player.velocity = Vector3(0.0, 0.5, -2.0)
	vault.handplant_height = 1.0
	vault.vault_onto = false
	assert_eq(vault.update_active_vault_type(0.1), 3, "a 1 m over plan at 2 m/s is not vaultOver")
	vault.vault_onto = true
	assert_eq(vault.update_active_vault_type(0.1), 1, "a 1 m onto plan at 2 m/s is not the step-up")
	player.movement_state = Move.GRAB
	assert_eq(vault.update_active_vault_type(9.0), 3, "a vault from a hang is not row 3")

# --- the catch ---------------------------------------------------------------------------

## [ME:CONFIRMED decompile 0x011f9c30] IntoGrab's reach scales with the speed
## toward the hang point: 0.4 of IntoGrabMaxDistance at rest, all of it from
## 200 uu/s.
func test_into_grab_reach_scales_with_the_approach_speed() -> void:
	var player: Player = await _player()
	_face(player, PI)
	var into: IntoGrabMove = player.move_manager.move_for(Move.INTO_GRAB)
	player.move_ledge_normal = Vector3.UP
	player.move_normal = Vector3(0.0, 0.0, -1.0)
	var here: Vector3 = player.global_position
	# The hang point 1.5 m ahead: beyond 80 uu, inside 200.
	player.move_ledge_location = here + Vector3(0.0, 0.928 - 0.1, 1.5)
	player.velocity = Vector3(0.0, -0.1, 0.0)
	assert_false(into.can_do_move_native(), "reached 1.5 m from rest")
	player.velocity = Vector3(0.0, -0.1, 2.0)
	assert_true(into.can_do_move_native(), "did not reach 1.5 m at 2 m/s toward it")

## The catch hangs the body at the hang point, square to the wall, with no
## physics and no collision.
func test_a_catch_hangs_still_at_the_hang_point() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 1.0), Vector3(0.0, 1.5, -0.5))
	await step(1)
	var grab: GrabMove = _hang(player, 3.0, 0.0)
	assert_eq(player.move_manager.current_name, Move.GRAB, "the catch did not hang")
	assert_eq(player.physics, Move.PHYS_NONE, "the hang has physics")
	assert_false(player.collide_world, "the hang collides")
	var at: Vector3 = player.global_position
	await step(10)
	assert_almost_eq(player.global_position.distance_to(at), 0.0, 0.001, "the hang moved")
	assert_eq(grab.grab_type, GrabMove.GrabType.LEGS_ON_WALL, "a hang on a wall reads as free")

# --- the hang ----------------------------------------------------------------------------

## [ME:CONFIRMED decompile N4 §1.1, 0x01207a70] Grab's PrePhysics -- the
## ledge probe 5 uu to the side that finds the corner -- runs only under
## physics: performPhysics is skipped under PHYS_None. An idle hang next to an
## outside corner stays put; a shimmy (PHYS_Flying) toward it goes round.
func test_only_a_shimmy_finds_the_corner_round_a_ledge_end() -> void:
	var player: Player = await _player()
	# A block whose right end is 3 cm right of the hands.
	_box(Vector3(2.0, 3.0, 2.0), Vector3(-0.97, 1.5, -1.0))
	await step(1)
	var grab: GrabMove = _hang(player, 3.0, 0.0)
	var at: Vector3 = player.global_position
	await step(45)
	assert_eq(grab.current_shimmy_move, GrabMove.ShimmyType.NO_SHIMMY,
		"an idle hang at a corner set off by itself")
	assert_almost_eq(player.global_position.distance_to(at), 0.0, 0.001, "the idle hang moved")
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(1.0, 0.0)
	for i in 30:
		await step(1)
		if grab.current_shimmy_move == GrabMove.ShimmyType.AROUND_CORNER:
			break
	assert_eq(grab.current_shimmy_move, GrabMove.ShimmyType.AROUND_CORNER,
		"a shimmy to the corner did not go round it")

## [ME:CONFIRMED decompile 0x011f7d60] THE QUIRK: the shimmy's time-out
## compares the SIGNED speed, so only a left shimmy times out on ShimmyTime;
## a right one goes on.
func test_only_a_left_shimmy_times_out() -> void:
	var player: Player = await _player()
	var grab: GrabMove = player.move_manager.move_for(Move.GRAB)
	for speed in [-0.6, 0.6]:
		grab.current_shimmy_move = GrabMove.ShimmyType.SHIMMY
		grab.shimmy_velocity = speed
		grab.shimmy_time = 0.01
		player.anim_slot.clear()
		player.anim_slot.play(&"HangStrafeRight", 1.0, 0.0, 0.0, false, false, player.pawn_yaw)
		grab.custom_anim_node = &"HangStrafeRight"
		# Past 0.8 of the strafe, where an abort is taken.
		player.anim_slot.advance(0.9)
		grab.update_shimmy(DT)
		var stopped: bool = grab.current_shimmy_move == GrabMove.ShimmyType.NO_SHIMMY
		if speed < 0.0:
			assert_true(stopped, "the left shimmy did not time out")
		else:
			assert_false(stopped, "the right shimmy timed out")

# --- the jump off --------------------------------------------------------------------------

## [ME:CONFIRMED decompile, N5 §13] THE QUIRK: GrabJump applies its velocity
## 0.1 s after it starts; until then the body falls from rest under the
## doubled script gravity, 0.5 x 1600 x 0.01 = 8 uu. The jump's own height is
## then 160 uu exactly.
func test_grab_jump_drops_before_it_jumps() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 1.0), Vector3(0.0, 1.5, -0.5))
	await step(1)
	_hang(player, 3.0, 0.0)
	# The view turned straight out from the wall.
	player.rotation.y = PI
	var start_y: float = player.global_position.y
	assert_true(player.move_manager.handle_move_action(Move.MA_JUMP), "jump did not leave the hang")
	assert_eq(player.move_manager.current_name, Move.GRAB_JUMP, "the jump off is not GrabJump")
	var jump: GrabJumpMove = player.move_manager.move_for(Move.GRAB_JUMP)
	assert_almost_eq(jump.jump_velocity.y, 2.0 * sqrt(8.0 * 1.6), 0.001, "Vz is not 2 sqrt(g h)")
	await step(6)
	assert_almost_eq(start_y - player.global_position.y, 0.08, 0.02, "the body did not drop 8 uu first")

## [ME:CONFIRMED decompile script TdPlayerController PlayerGrabbing,
## SetInputHint] Entering PlayerGrabbing clears bLeftThumbStickPassedDeadZone,
## and only a stick back inside 0.3 on both axes sets it again; until then
## there is no hint, so forward held from before the catch never makes
## ClimbUpLong (forward x10 past 8 WITH the hint Up). Let go and pushed again,
## it does, on the frame of the push. Jump pulls up whatever the stick does.
func test_forward_held_into_a_hang_climbs_only_once_pushed_again() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
	await step(1)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	await step(3)
	_hang(player, 3.0, 0.0)
	await step(90)
	assert_eq(player.move_manager.current_name, Move.GRAB, "forward held into the hang climbed")
	assert_eq(player.move_action_hint, Move.MAH_NONE, "forward held into the hang gave a hint")
	input.hold_move(0.0, 0.0)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.GRAB, "letting go climbed")
	input.hold_move(0.0, 1.0)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.GRAB_PULL_UP, "pushing forward again did not climb")

func test_jump_from_a_hang_pulls_up_whatever_the_stick_does() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
	await step(1)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	await step(3)
	_hang(player, 3.0, 0.0)
	await step(90)
	input.press_jump()
	await step(1)
	input.release_jump()
	assert_eq(player.move_manager.current_name, Move.GRAB_PULL_UP, "jump from the hang did not pull up")

# --- the pull-up's room ------------------------------------------------------------------

## The ledge's wall and what stands over it as ONE body, the way a level mesh
## is: each part a box shape of `[size, centre]`.
func _one_body(parts: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	for part in parts:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[0]
		shape.shape = box
		shape.position = part[1]
		body.add_child(shape)
	get_tree().root.add_child(body)
	_extra.append(body)
	return body

## [ME:CONFIRMED decompile script TdMove_GrabPullUp.CanDoMove,
## TdPhysicsMove.CanHeaveOverLedge] The pull-up asks for room: the body's box
## raised from the hang to the ledge plus its height, then swept over the top.
## A ceiling 30 cm over the ledge leaves room for neither the standing nor the
## crouched body, so it is refused -- and the jump falls through to GrabJump,
## which only goes with the view turned from the wall. The ceiling belongs to
## the wall's own body: the hang starts every one of those sweeps touching it.
func test_a_ceiling_over_the_ledge_refuses_the_pull_up() -> void:
	var player: Player = await _player()
	_one_body([[Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0)],
		[Vector3(4.0, 0.5, 3.0), Vector3(0.0, 3.55, -1.0)]])
	await step(1)
	_hang(player, 3.0, 0.0)
	await step(70)
	assert_false(player.move_manager.can_do(Move.GRAB_PULL_UP), "a pull-up under a ceiling was allowed")
	assert_false(player.move_manager.handle_move_action(Move.MA_JUMP), "jump did something facing the wall")
	assert_eq(player.move_manager.current_name, Move.GRAB, "the hang was left facing the wall")
	player.rotation.y = PI
	assert_true(player.move_manager.handle_move_action(Move.MA_JUMP), "jump did not leave the hang")
	assert_eq(player.move_manager.current_name, Move.GRAB_JUMP, "the refused pull-up did not fall through to GrabJump")

## [ME:CONFIRMED decompile script TdMove_GrabPullUp] A floor more than
## Pawn.MaxStepHeight (35 uu) under the ledge is a heave OVER the wall, not a
## pull-up onto it: 37 uu down behind a 10 cm wall plays the heave over.
func test_a_floor_37_uu_below_the_ledge_is_heaved_over() -> void:
	var player: Player = await _player()
	_one_body([[Vector3(4.0, 3.0, 0.1), Vector3(0.0, 1.5, -0.05)],
		[Vector3(4.0, 2.63, 3.0), Vector3(0.0, 1.315, -1.6)]])
	await step(1)
	_hang(player, 3.0, 0.0)
	await step(70)
	assert_true(player.move_manager.can_do(Move.GRAB_PULL_UP), "no room to go over a thin wall")
	var pull: GrabPullUpMove = player.move_manager.move_for(Move.GRAB_PULL_UP)
	assert_almost_eq(pull.floor_over_ledge_location.y, 2.63, 0.01, "the floor behind the wall was not found")
	player.move_manager.set_move(Move.GRAB_PULL_UP)
	assert_eq(player.anim_slot.current_name(), &"HangHeaveOver", "37 uu down was not heaved over")

# --- ladders -----------------------------------------------------------------------------

## [ME:CONFIRMED decompile TdMove_Climb.HasFloorBelow] THE QUIRK: the floor
## test traces from a point to itself and never hits.
func test_the_ladder_floor_test_never_finds_a_floor() -> void:
	var player: Player = await _player()
	var line: InterestLine = _line(InterestLine.Kind.LADDER, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 4.0, -1.0))
	await step(1)
	var climb: ClimbMove = player.move_manager.move_for(Move.CLIMB)
	climb.ladder = LadderVolume.new(line)
	player.global_position = climb.ladder.get_ladder_location(0)
	assert_false(climb.has_floor_below(), "the floor test found the floor")

## Steps are StepHeight (32 uu) apart, the body held 50 uu out from a step
## that sits 1 uu out from the line.
func test_ladder_steps_are_step_height_apart() -> void:
	var player: Player = await _player()
	var line: InterestLine = _line(InterestLine.Kind.LADDER, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 4.0, -1.0))
	await step(1)
	var ladder := LadderVolume.new(line)
	var a: Vector3 = ladder.get_ladder_location(2)
	var b: Vector3 = ladder.get_ladder_location(3)
	assert_almost_eq(b.y - a.y, 0.32, 0.0001, "steps are not 32 uu apart")
	assert_eq(ladder.get_closest_step(b.y + 0.1), 3, "the closest step is not the nearest by height")
	assert_almost_eq(Vector2(a.x, a.z).distance_to(Vector2(0.0, -1.0)), 0.51, 0.0001,
		"the body is not held 50 uu out from the step")
	assert_true(player != null)

## [ME:CONFIRMED decompile 0x012ab620] The builder hangs the steps from the
## top: the top step 96 uu under the top end, the rest every 32 uu down to
## a TRUNCATED count above one step over the bottom end. 400 uu: top step at
## 304, trunc((304 - 32) / 32) = 8 steps under it, the lowest at 48.
func test_ladder_steps_hang_from_the_top_by_a_truncated_count() -> void:
	var player: Player = await _player()
	var line: InterestLine = _line(InterestLine.Kind.LADDER, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 4.0, -1.0))
	await step(1)
	var ladder := LadderVolume.new(line)
	assert_eq(ladder.steps.size(), 9, "not trunc(range / 32) + 1 steps")
	assert_almost_eq(ladder.steps[ladder.steps.size() - 1].y, 3.04, 0.0001, "the top step is not 96 uu under the top")
	assert_almost_eq(ladder.steps[0].y, 0.48, 0.0001, "the lowest step is not where the truncation leaves it")
	assert_eq(ladder.get_last_step(), 8, "a ladder's last step is not its top one")
	assert_eq(ladder.get_ladder_location(99), ladder.get_ladder_location(8), "a location past the top is not clamped")
	line.pipe = true
	var pipe := LadderVolume.new(line)
	assert_eq(pipe.get_last_step(), 5, "a pipe's last step is not three under its top")
	assert_eq(pipe.top_index(), 8, "IntoClimb's topmost step is not the last of the steps")
	assert_eq(pipe.get_closest_step(5.0), 8, "the closest step left out a pipe's top three")
	assert_almost_eq(pipe.get_ladder_location(0).y, 0.43, 0.0001, "a pipe's body is not held 5 uu lower")
	assert_true(player != null)

# --- balance ------------------------------------------------------------------------------

## [ME:CONFIRMED emulated 0x0120a280] One frame of the balance factor at
## rest, looking along the beam, no stick: only the unstable term,
## 0.3 sin(BF pi / 2) dt.
func test_balance_factor_runs_away_from_level() -> void:
	var player: Player = await _player()
	var beam: InterestLine = _line(InterestLine.Kind.BALANCE, Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, -8.0))
	await step(1)
	var balance: BalanceMove = player.move_manager.move_for(Move.BALANCE)
	_face(player, 0.0)
	balance.volume = beam
	player.move_manager.set_move(Move.BALANCE)
	balance.use_precise_rotation = false
	balance.balance_factor = 0.5
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	balance.pre_physics(DT)
	assert_almost_eq(balance.balance_factor, 0.5 + 0.3 * sin(0.25 * PI) * DT, 1e-5,
		"the balance factor does not follow 0.3 sin(BF pi / 2)")

## The beam forces first person for the ride (this project's presentation):
## over a saved third-person preference, which survives; handed back the
## moment the balance is lost, and on any other way off.
func test_the_beam_forces_first_person_until_the_balance_is_lost() -> void:
	for lose_balance in [false, true]:
		var player: Player = await _player()
		player.camera_rig.third_person = true
		var beam: InterestLine = _line(InterestLine.Kind.BALANCE, Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, -8.0))
		await step(1)
		var balance: BalanceMove = player.move_manager.move_for(Move.BALANCE)
		_face(player, 0.0)
		balance.volume = beam
		player.move_manager.set_move(Move.BALANCE)
		await step(2)
		assert_false(player.camera_rig.in_third_person(), "the beam did not force first person")
		assert_true(player.camera_rig.third_person, "forcing the view overwrote the saved preference")
		if lose_balance:
			balance.falloff()
		else:
			player.move_manager.set_move(Move.WALKING)
		await step(2)
		assert_true(player.camera_rig.in_third_person(),
			"the view was not handed back (balance lost: %s)" % lose_balance)
		TestWorld.teardown(_world)
		_world = {}
		for node in _extra:
			node.queue_free()
		_extra.clear()
		await step(1)

# --- the ledge walk's presentation (this project's) -----------------------------------

## A ledge along X with the wall at -Z (front() faces -Z, so WallNormal is +Z):
## the pawn backs onto it facing +Z, Godot yaw PI. The body walks up to it
## facing the wall, yaw 0.
func _ledge_walk(player: Player, third: bool) -> LedgeWalkMove:
	player.camera_rig.third_person = third
	var y: float = player.global_position.y
	var line: InterestLine = _line(InterestLine.Kind.LEDGE_WALK, Vector3(-5.0, y, 0.0), Vector3(5.0, y, 0.0))
	await step(1)
	_face(player, 0.0)
	var ledge: LedgeWalkMove = player.move_manager.move_for(Move.LEDGE_WALK)
	ledge.volume = line
	player.move_manager.set_move(Move.LEDGE_WALK)
	await step(60)
	assert_eq(player.move_manager.current_name, Move.LEDGE_WALK, "test setup: not on the ledge")
	return ledge

func _yaw_off(a: float, b: float) -> float:
	return absf(rad_to_deg(wrapf(a - b, -PI, PI)))

func _clear_world() -> void:
	TestWorld.teardown(_world)
	_world = {}
	for node in _extra:
		node.queue_free()
	_extra.clear()
	await step(1)

## The pawn backs onto the wall in both views (the original's); the MODEL and
## the camera face the wall in third person, and the view is held round the
## wall there rather than pulled off it.
func test_the_third_person_ledge_walk_faces_the_wall() -> void:
	for third in [false, true]:
		var player: Player = await _player()
		await _ledge_walk(player, third)
		assert_lt(_yaw_off(player.pawn_yaw, PI), 2.0, "the pawn does not back onto the wall")
		var model_wanted: float = 0.0 if third else PI
		assert_lt(_yaw_off(player.visual_yaw(), model_wanted), 5.0,
			"the model faces %.0f, not %.0f (third person %s)"
				% [rad_to_deg(player.visual_yaw()), rad_to_deg(model_wanted), third])
		assert_lt(_yaw_off(player.rotation.y, model_wanted), 60.0,
			"the view was not held round the model's facing (third person %s)" % third)
		await _clear_world()

## D goes to the screen's right in both views: the model's own right, which is
## the pawn's left while the model faces the wall.
func test_d_shuffles_to_the_models_right_in_both_views() -> void:
	for third in [false, true]:
		var player: Player = await _player()
		await _ledge_walk(player, third)
		var model_right: Vector3 = Basis(Vector3.UP, player.visual_yaw()) * Vector3.RIGHT
		var before: Vector3 = player.global_position
		var input: ScriptedInputSource = _world["input"]
		input.hold_move(1.0, 0.0)
		await step(30)
		input.hold_move(0.0, 0.0)
		var moved: Vector3 = player.global_position - before
		assert_gt(moved.dot(model_right), 0.05,
			"D did not move the body to the model's right (third person %s, %.2f m)" % [third, moved.dot(model_right)])
		await _clear_world()

## Switching views mid-ledge turns the model round in place over turn_time,
## with no travel meanwhile.
func test_switching_views_mid_ledge_turns_the_model_round() -> void:
	var player: Player = await _player()
	var ledge: LedgeWalkMove = await _ledge_walk(player, true)
	assert_lt(_yaw_off(player.visual_yaw(), 0.0), 5.0, "test setup: the model does not face the wall")
	player.camera_rig.third_person = false
	await step(2)
	assert_true(ledge.is_turning(), "the view change did not start a turn")
	var before: Vector3 = player.global_position
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(1.0, 0.0)
	await step(10)
	assert_lt(player.global_position.distance_to(before), 0.01, "the body travelled while turning round")
	input.hold_move(0.0, 0.0)
	await step(int(ledge._ledge_cfg().turn_time * 60.0) + 10)
	assert_false(ledge.is_turning(), "the turn never ended")
	assert_lt(_yaw_off(player.visual_yaw(), PI), 5.0, "the model did not turn round to back onto the wall")

## Third person: the head watches the way the body last shuffled, and the
## ledge's own pitch; first person leaves the head to the view.
func test_the_third_person_head_watches_the_shuffle() -> void:
	for third in [false, true]:
		var player: Player = await _player()
		var ledge: LedgeWalkMove = await _ledge_walk(player, third)
		var input: ScriptedInputSource = _world["input"]
		input.hold_move(1.0, 0.0)
		await step(10)
		input.hold_move(0.0, 0.0)
		await step(10)
		if third:
			assert_false(is_nan(ledge.head_yaw_override()), "the head lost the shuffle once the key was let go")
			assert_lt(ledge.head_yaw_override(), 0.0, "the head does not look to the model's right")
			assert_false(is_nan(ledge.head_pitch_override()), "the head pitch is not the ledge's")
		else:
			assert_true(is_nan(ledge.head_yaw_override()), "the first-person head was turned off the view")
			assert_true(is_nan(ledge.head_pitch_override()), "the first-person head was pitched off the view")
		await _clear_world()

# --- the movement-volume spline ------------------------------------------------------

## [ME:CONFIRMED decompile 0x012a9490 / 0x012a9580] The spline is a quadratic
## Bezier whose samples are the line's points: the control point recovered
## from them puts every sample back where it was, and the slope is the
## Bezier's direction, not a segment's.
func test_the_spline_is_the_bezier_its_points_were_sampled_from() -> void:
	var s := MovementSpline.new()
	var a := Vector3(0.0, 4.0, 0.0)
	var m := Vector3(5.0, 0.0, 0.0)
	var b := Vector3(10.0, 4.0, 0.0)
	for i in 11:
		var t: float = i / 10.0
		s.locations.append(a * (1.0 - t) * (1.0 - t) + m * 2.0 * t * (1.0 - t) + b * t * t)
	s._fit()
	assert_almost_eq(s.middle, m, Vector3.ONE * 1e-4, "the control point is not the samples' own")
	assert_almost_eq(s.location_at(0.3), s.locations[3], Vector3.ONE * 1e-4, "GetLocationOnSpline is off its samples")
	assert_almost_eq(s.slope_at(0.5), Vector3.RIGHT, Vector3.ONE * 1e-4, "the slope at the bottom is not level")
	assert_almost_eq(s.slope_at(2.0), s.slope_at(1.0), Vector3.ONE * 1e-6, "the parameter is not clamped")

## [ME:CONFIRMED decompile 0x012a9740] The closest point is projected on its
## segment WITHOUT a clamp, and its parameter is the segment plus |s|: past
## the end it runs on along the line, behind the start it counts forward.
func test_the_closest_point_is_unclamped_and_its_parameter_is_absolute() -> void:
	var s := MovementSpline.new()
	s.locations = PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)])
	s._fit()
	var past: Array = s.find_closest(Vector3(3.0, 1.0, 0.0))
	assert_almost_eq(past[0], Vector3(3.0, 0.0, 0.0), Vector3.ONE * 1e-5, "the point past the end was clamped")
	assert_almost_eq(past[1], 2.0, 1e-5, "the parameter past the end is not the last segment's full length")
	var behind: Array = s.find_closest(Vector3(-0.25, 0.0, 0.0))
	assert_almost_eq(behind[0], Vector3(-0.25, 0.0, 0.0), Vector3.ONE * 1e-5, "the point behind the start was clamped")
	assert_almost_eq(behind[1], 0.25, 1e-5, "a point behind the start does not count forward")

# --- end to end ------------------------------------------------------------------

## Runs the body toward -Z for `seconds`, the stick fully forward.
func _run(player: Player, seconds: float) -> void:
	_face(player, 0.0)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	await step(int(seconds * 60.0))

## A jump at a waist-high box at a run is the original's vault: VaultOver,
## through CheckAutoMoves (Jump asks for vaults; walking does not), over the
## top and down the far side.
func test_a_jump_at_a_waist_high_box_vaults_it() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 1.0, 0.4), Vector3(0.0, 0.5, -8.0))
	await step(1)
	await _run(player, 1.0)
	var input: ScriptedInputSource = _world["input"]
	var seen: Array[StringName] = []
	for i in 120:
		if player.global_position.z < -6.6 and not seen.has(Move.JUMP):
			input.press_jump()
		await step(1)
		if not seen.has(player.move_manager.current_name):
			seen.append(player.move_manager.current_name)
		if player.global_position.z < -9.0:
			break
	assert_true(seen.has(Move.VAULT_OVER), "no vault in %s" % [seen])
	assert_lt(player.global_position.z, -8.2, "the body did not end beyond the box")

## A jump at a wall with its top at hand height from the jump's apex: the
## hand-plant search finds the top, IntoGrab reaches for it, and the body
## hangs.
func test_a_jump_at_a_wall_hangs_from_its_top() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 2.4, 1.0), Vector3(0.0, 1.2, -3.5))
	await step(1)
	_face(player, 0.0)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	await step(30)
	input.press_jump()
	await step(1)
	input.hold_move(0.0, 0.0)
	var seen: Array[StringName] = []
	for i in 120:
		await step(1)
		if not seen.has(player.move_manager.current_name):
			seen.append(player.move_manager.current_name)
		if player.move_manager.current_name == Move.GRAB:
			break
	assert_eq(player.move_manager.current_name, Move.GRAB, "no hang: %s" % [seen])
	assert_true(seen.has(Move.INTO_GRAB), "the hang was not reached through IntoGrab: %s" % [seen])

## Jump while hanging square to the wall is the pull-up: the animation's root
## motion carries the body up and over, and its end leaves it walking on top.
func test_a_pull_up_ends_on_top() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
	await step(1)
	_hang(player, 3.0, 0.0)
	await step(70)
	assert_true(player.move_manager.handle_move_action(Move.MA_JUMP), "jump did not leave the hang")
	assert_eq(player.move_manager.current_name, Move.GRAB_PULL_UP, "the jump was not a pull-up")
	for i in 150:
		await step(1)
		if player.move_manager.current_name != Move.GRAB_PULL_UP:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING, "the pull-up did not end walking")
	var feet: float = player.global_position.y - player.collision_half_height()
	assert_almost_eq(feet, 3.0, 0.1, "the feet are not on the top (%.2f)" % feet)

## Walking into a ladder's volume with the stick forward gets onto it
## (IntoClimb, then Climb); a climb up takes one step of 32 uu.
func test_a_ladder_is_got_onto_and_climbed() -> void:
	var player: Player = await _player()
	# The rungs on a wall at z = -1.5; the volume's front faces +Z, out of it.
	_box(Vector3(2.0, 4.0, 1.0), Vector3(0.0, 2.0, -2.0))
	var line: InterestLine = _line(InterestLine.Kind.LADDER, Vector3(0.0, 0.0, -1.45),
		Vector3(0.0, 4.0, -1.45), PI)
	await step(1)
	_face(player, 0.0)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	var seen: Array[StringName] = []
	for i in 120:
		await step(1)
		if not seen.has(player.move_manager.current_name):
			seen.append(player.move_manager.current_name)
		if player.move_manager.current_name == Move.CLIMB:
			break
	assert_eq(player.move_manager.current_name, Move.CLIMB, "not on the ladder: %s" % [seen])
	assert_true(seen.has(Move.INTO_CLIMB), "the ladder was not got onto through IntoClimb: %s" % [seen])
	var ladder: LadderVolume = (player.move_manager.move_for(Move.CLIMB) as ClimbMove).ladder
	assert_not_null(ladder)
	var step0: int = ladder.get_closest_step(player.global_position.y)
	await step(30)
	assert_gt(ladder.get_closest_step(player.global_position.y), step0, "holding forward did not climb")
	assert_true(line != null)

## [ME:CONFIRMED decompile] GrabPullUp.StartMove: ResetCameraLook(DisableLookTime),
## a view pitched up on the hang is brought level over the pull-up's 0.2 s.
func test_a_pull_up_brings_the_view_level() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
	await step(1)
	_hang(player, 3.0, 0.0)
	await step(70)
	player.camera_rig.set_pitch(deg_to_rad(30.0))
	assert_true(player.move_manager.handle_move_action(Move.MA_JUMP), "jump did not leave the hang")
	assert_eq(player.move_manager.current_name, Move.GRAB_PULL_UP, "the jump was not a pull-up")
	await step(6)
	var half: float = rad_to_deg(player.camera_rig.view_pitch())
	assert_between(half, 1.0, 29.0, "the reset is not eased over its 0.2 s")
	await step(8)
	assert_almost_eq(player.camera_rig.view_pitch(), 0.0, 0.01, "the pull-up left the view pitched")

## The pull-up's pitch floor is the first-person eye's (the original's 0 ..
## 16384); in third person the pitch is free, so the camera can rise over the
## body to watch the climb (GrabPullUpMove.third_person_pitch_limits()).
func test_the_pull_up_frees_the_third_person_pitch() -> void:
	for third in [false, true]:
		var player: Player = await _player()
		player.camera_rig.third_person = third
		_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
		await step(1)
		_hang(player, 3.0, 0.0)
		await step(70)
		assert_true(player.move_manager.handle_move_action(Move.MA_JUMP), "jump did not leave the hang")
		assert_eq(player.move_manager.current_name, Move.GRAB_PULL_UP, "the jump was not a pull-up")
		await step(20)
		var input: ScriptedInputSource = _world["input"]
		var lowest := 0.0
		for i in 20:
			input.state.look = Vector2(0.0, 40.0)
			await step(1)
			lowest = minf(lowest, rad_to_deg(player.camera_rig.view_pitch()))
		input.state.look = Vector2.ZERO
		if third:
			assert_lt(lowest, -10.0, "the third-person pull-up still held the pitch at level")
		else:
			assert_gt(lowest, -1.0, "the first-person pull-up looked down (%.1f)" % lowest)
		TestWorld.teardown(_world)
		_world = {}
		for node in _extra:
			node.queue_free()
		_extra.clear()
		await step(1)

## A railing of ordinary thickness at chest height is vaulted, not climbed:
## the hand-plant search finds its top (result 2) under MinWallHeight, so
## WallClimb refuses it and nothing draws the view up.
func test_a_jump_at_a_railing_vaults_it_without_a_climb() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 1.5, 0.1), Vector3(0.0, 0.75, -6.0))
	await step(1)
	_face(player, 0.0)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	var seen: Array[StringName] = []
	var top := 0.0
	var jumped := false
	for i in 200:
		if not jumped and player.global_position.z < -4.5:
			input.press_jump()
			jumped = true
		await step(1)
		input.release_jump()
		if not seen.has(player.move_manager.current_name):
			seen.append(player.move_manager.current_name)
		top = maxf(top, absf(player.camera_rig.view_pitch()))
		if player.global_position.z < -7.5:
			break
	assert_true(seen.has(Move.VAULT_OVER), "no vault in %s" % [seen])
	assert_false(seen.has(Move.WALL_CLIMB), "the railing was climbed: %s" % [seen])
	assert_almost_eq(top, 0.0, 0.01, "the vault drew the view off level")

## An Area3D of `script_class` with a 1 m box at `at`, under `parent`.
func _volume(area: Area3D, at: Vector3, parent: Node = null) -> Area3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	area.add_child(shape)
	if parent == null:
		get_tree().root.add_child(area)
		_extra.append(area)
	else:
		parent.add_child(area)
	area.global_position = at
	return area

## [ME:CONFIRMED decompile N5 §11] IntoGrab's last gate refuses a ledge point
## inside ANY TdMovementVolume: the interest lines' volumes, a fall-height
## volume, the barbed wire's. A volume of this project's own is none of them.
func test_into_grab_refuses_a_ledge_in_any_movement_volume() -> void:
	var player: Player = await _player()
	_volume(FallHeightVolume.new(), Vector3(5.0, 1.0, 0.0))
	var wire := BarbedWire.new()
	get_tree().root.add_child(wire)
	_extra.append(wire)
	_volume(ModifierVolume.new(), Vector3(-5.0, 1.0, 0.0), wire)
	_volume(ModifierVolume.new(), Vector3(0.0, 1.0, 5.0))
	await step(2)
	assert_true(player.in_movement_volume(Vector3(5.0, 1.0, 0.0)), "a fall-height volume was not found")
	assert_true(player.in_movement_volume(Vector3(-5.0, 1.0, 0.0)), "the barbed wire was not found")
	assert_false(player.in_movement_volume(Vector3(0.0, 1.0, 5.0)), "a modifier volume counted")
	assert_false(player.in_movement_volume(Vector3(0.0, 1.0, -5.0)), "empty space counted")

## [ME:CONFIRMED decompile TdMove_Grab.UpdateGrabType] The legs changing
## between wall and free swap the strafe animation without restarting it: the
## new one starts where the last had got to.
func test_a_grab_type_change_keeps_the_strafe_where_it_was() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
	await step(1)
	var grab: GrabMove = _hang(player, 3.0, 0.0)
	await step(70)
	grab.play_slot_anim(&"HangStrafeRight", 1.0, 0.0, 0.0)
	player.anim_slot.set_position(0.4)
	grab.update_grab_type(true)
	var now: CustomAnimSlot.Channel = player.anim_slot.current()
	assert_ne(now.name, &"HangStrafeRight", "test setup: the strafe did not change")
	assert_almost_eq(now.sequence_time(), 0.4, 0.001, "the new strafe started over")

# --- the model follows the pawn (this project's presentation) -------------------------

## A hang reached with no key held squares the MODEL to the wall, not only the
## pawn: "not following the camera" is the rule for a body standing about,
## and a move that turns the body by a hand on the wall owes the model that
## facing. Eased, not snapped.
func test_a_hang_squares_the_model_to_the_wall() -> void:
	var player: Player = await _player()
	_box(Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0))
	await step(1)
	player.pin_visual_yaw(deg_to_rad(90.0))
	_hang(player, 3.0, 0.0)
	await step(1)
	assert_gt(_yaw_off(player.visual_yaw(), player.pawn_yaw), 30.0, "the model was snapped round in one tick")
	await step(30)
	assert_lt(_yaw_off(player.visual_yaw(), player.pawn_yaw), 2.0,
		"the model hangs %.0f degrees off the wall" % _yaw_off(player.visual_yaw(), player.pawn_yaw))
