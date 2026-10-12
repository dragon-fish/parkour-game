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

## [ME:CONFIRMED decompile 0x01207a70] THE QUIRK: an idle hang probes the
## ledge 5 uu to its right every frame, and where that finds no top it asks
## for the corner round to the right -- so next to an outside corner the
## corner shimmy starts with no input at all.
func test_an_idle_hang_at_an_outside_corner_starts_round_it() -> void:
	var player: Player = await _player()
	# A block whose right end is 3 cm right of the hands.
	_box(Vector3(2.0, 3.0, 2.0), Vector3(-0.97, 1.5, -1.0))
	await step(1)
	var grab: GrabMove = _hang(player, 3.0, 0.0)
	await step(2)
	assert_eq(grab.current_shimmy_move, GrabMove.ShimmyType.AROUND_CORNER,
		"an idle hang at a corner did not go round it")

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

## Steps are StepHeight (32 uu) apart, out from the ladder by 50 uu.
func test_ladder_steps_are_step_height_apart() -> void:
	var player: Player = await _player()
	var line: InterestLine = _line(InterestLine.Kind.LADDER, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 4.0, -1.0))
	await step(1)
	var ladder := LadderVolume.new(line)
	var a: Vector3 = ladder.get_ladder_location(2)
	var b: Vector3 = ladder.get_ladder_location(3)
	assert_almost_eq(b.y - a.y, 0.32, 0.0001, "steps are not 32 uu apart")
	assert_eq(ladder.get_closest_step(b.y + 0.1), 3, "the closest step does not round")
	assert_almost_eq(Vector2(a.x, a.z).distance_to(Vector2(0.0, -1.0)), 0.5, 0.0001,
		"the body is not held 50 uu out")
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
