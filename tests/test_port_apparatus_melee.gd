extends ParkourTest

# The apparatus and melee family of the faithful port: Swing, SwingJump,
# ZipLine with IntoZipLine, Barge, the melee moves and Interact, and the
# flying physics they run on. [ME:CONFIRMED decompile N5 §0.1, §16, §17, §20,
# §21; scripts] The original's arithmetic and its quirks -- no tuning values.

const TestWorld = preload("res://tests/world_fixture.gd")
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

func _start() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

func _line(kind: InterestLine.Kind, points: Array) -> InterestLine:
	var line := InterestLine.new()
	line.kind = kind
	var curve := Curve3D.new()
	for p in points:
		curve.add_point(p)
	line.curve = curve
	get_tree().root.add_child(line)
	_extra.append(line)
	return line

func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = at
	_extra.append(body)
	return body

# --- the flying physics ------------------------------------------------------------

## [ME:CONFIRMED decompile N1 §3, N5 §0.1] bFluid: after the tenth-strength
## drag, the whole velocity is scaled by (1 - dt * Friction).
func test_the_fluid_term_scales_the_velocity_after_the_drag() -> void:
	var r: Array = PawnPhysics.calc_velocity(Vector3(10.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO,
		0.1, 24.0, 0.15, false, 1.0, 61.44, 1.0, false, false, false, Vector3.FORWARD, true)
	assert_almost_eq((r[0] as Vector3).x, 10.0 * (1.0 - 0.1 * 0.15 * 0.1) * (1.0 - 0.1 * 0.15), 1e-5)

## The flying physics clamps at AirSpeed, 2400 uu/s.
func test_flying_is_clamped_at_air_speed() -> void:
	var r: Array = PawnPhysics.calc_velocity(Vector3(40.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO,
		DT, 24.0, 0.15, false, 1.0, 61.44, 1.0, false, false, false, Vector3.FORWARD, true)
	assert_almost_eq((r[0] as Vector3).length(), 24.0, 1e-4)

# --- Swing -------------------------------------------------------------------------

## A bar along +X, out of the body's reach so its volume asks nothing. Its
## volume X axis is -Z: a body on the +Z side swings toward -Z.
func _far_bar() -> InterestLine:
	return _line(InterestLine.Kind.SWING, [Vector3(18.5, 10.0, -20.0), Vector3(21.5, 10.0, -20.0)])

func _hang(player: Player, bar: InterestLine, angle: float, velocity := Vector3.ZERO) -> SwingMove:
	var grip: Vector3 = SwingMove.volume_location(bar)
	player.global_position = grip + 1.2 * (sin(angle) * Vector3(0.0, 0.0, -1.0) - cos(angle) * Vector3.UP)
	player.velocity = velocity
	var swing: SwingMove = player.move_manager.move_for(Move.SWING)
	swing.volume = bar
	player.move_manager.set_move(Move.SWING)
	return swing

## [ME:CONFIRMED emulated] GetPawnAngle is the exact inverse of
## GetPawnLocation over -pi .. pi.
func test_the_pendulum_angle_and_location_are_inverses() -> void:
	var player: Player = await _start()
	var swing: SwingMove = player.move_manager.move_for(Move.SWING)
	swing.swing_location = Vector3(1.0, 5.0, 2.0)
	swing.swing_direction = Vector3(0.6, 0.0, -0.8)
	for a in [-3.1, -2.0, -1.0, -0.3, 0.0, 0.4, 1.2, 2.5, 3.1]:
		assert_almost_eq(swing.get_pawn_angle(swing.get_pawn_location(a)), a, 1e-4)

## [ME:CONFIRMED decompile N5 §25.8] The start angle goes through an INTEGER
## Clamp(int(a), int(-1.2), int(-0.7)): it is 0 or -1 rad, nothing between.
func test_the_start_angle_is_zero_or_minus_one_radian() -> void:
	var player: Player = await _start()
	var bar: InterestLine = _far_bar()
	for pair in [[-0.5, 0.0], [-0.99, 0.0], [-1.1, -1.0], [-2.5, -1.0]]:
		var swing: SwingMove = _hang(player, bar, pair[0])
		assert_eq(player.move_manager.current_name, Move.SWING)
		assert_eq(swing.swing_angle, float(pair[1]), "start angle for %.2f rad" % pair[0])
		player.move_manager.start(Move.WALKING)

## [ME:CONFIRMED decompile] SwingVelocity starts at MaxSwingVelocity *
## min(1, |V.xy| / 500 uu/s), and the body's own velocity is zeroed.
func test_the_swing_starts_from_the_flat_arrival_speed() -> void:
	var player: Player = await _start()
	var swing: SwingMove = _hang(player, _far_bar(), -0.5, Vector3(0.0, -4.0, -3.0))
	assert_almost_eq(swing.swing_velocity, 4.25 * 3.0 / 5.0, 1e-5)
	assert_eq(player.velocity, Vector3.ZERO)

## [ME:CONFIRMED emulated N5 §16] One frame of the pendulum: 10 sin(a) rad/s^2,
## 0.8/s damping, the cos(a) cap, and the body teleported onto the arc while
## its velocity stays zero.
func test_one_frame_of_the_pendulum_is_the_natives() -> void:
	var player: Player = await _start()
	var swing: SwingMove = _hang(player, _far_bar(), -0.5, Vector3(0.0, 0.0, -3.0))
	await step(15)
	assert_false(swing.is_interpolating_into, "test setup: still pulling onto the arc")
	var a0: float = swing.swing_angle
	var v: float = swing.swing_velocity
	v -= sin(a0) * DT * 10.0
	v -= v * DT * 0.8
	if a0 > 0.0:
		v = minf(v, cos(a0) * 4.25)
	if a0 < 0.0:
		v = maxf(v, -cos(a0) * 4.25)
	var a1: float = clampf(v * DT + a0, -PI, PI)
	await step(1)
	assert_almost_eq(swing.swing_velocity, v, 1e-4)
	assert_almost_eq(swing.swing_angle, a1, 1e-4)
	assert_true(player.global_position.is_equal_approx(swing.get_pawn_location(a1)),
		"the body is not on the arc")
	assert_eq(player.velocity, Vector3.ZERO, "the swing moved the body by velocity")

## [ME:CONFIRMED decompile N5 §16] 600 uu/s is the WHOLE exit speed:
## tangent * cos(min(pi/2, a - 1)) * 600, so exactly 6 m/s off a = 1 rad, with
## the 0.75 gravity window, into SwingJump.
func test_the_exit_is_600_cos_jump_angle_along_the_arc() -> void:
	var player: Player = await _start()
	var swing: SwingMove = _hang(player, _far_bar(), -0.5)
	await step(15)
	swing.swing_angle = 1.0
	player.global_position = swing.get_pawn_location(1.0)
	player.move_manager.handle_move_action(Move.MA_JUMP)
	assert_eq(player.move_manager.current_name, Move.SWING_JUMP)
	var tangent: Vector3 = cos(1.0) * swing.swing_direction + sin(1.0) * Vector3.UP
	assert_true(player.velocity.is_equal_approx(tangent * 6.0), "exit velocity %s" % player.velocity)
	assert_almost_eq(player.gravity_modifier, 0.75, 1e-6)

## [ME:CONFIRMED decompile] No jump while JumpAngle <= -pi/4, i.e. a below
## 1 - pi/4 = 0.2146 rad. A kick there asks MeleeAir with bCheckCanDo, which
## refuses every state but the five airborne ones -- and leaves
## PendingMovementState behind.
func test_below_the_window_the_jump_is_ignored_and_the_kick_never_lands() -> void:
	var player: Player = await _start()
	var swing: SwingMove = _hang(player, _far_bar(), -0.5)
	await step(15)
	swing.swing_angle = 0.2
	player.move_manager.handle_move_action(Move.MA_JUMP)
	assert_eq(player.move_manager.current_name, Move.SWING, "jumped below the window")
	swing.swing_angle = 1.0
	player.move_manager.handle_move_action(Move.MA_MELEE)
	assert_eq(player.move_manager.current_name, Move.SWING, "a kick left the bar")
	assert_eq(player.pending_movement_state, Move.MELEE_AIR, "the refused check left nothing behind")

## [ME:CONFIRMED decompile] LetGo: Falling with the swing's zero velocity.
func test_letting_go_drops_straight_down() -> void:
	var player: Player = await _start()
	var swing: SwingMove = _hang(player, _far_bar(), -0.5, Vector3(0.0, 0.0, -5.0))
	await step(15)
	assert_ne(swing.swing_velocity, 0.0, "test setup: the swing is not moving")
	player.move_manager.handle_move_action(Move.MA_CROUCH)
	assert_eq(player.move_manager.current_name, Move.FALLING)
	assert_eq(player.velocity, Vector3.ZERO)

## [ME:CONFIRMED decompile TdSwingVolume] The volume offers the swing to a
## body moving toward the bar and facing it; once it takes the body the
## volume is spent until the body enters it again.
func test_the_bar_catches_a_body_moving_at_it() -> void:
	var player: Player = await _start()
	var bar: InterestLine = _line(InterestLine.Kind.SWING,
		[Vector3(-1.5, 2.6, -1.0), Vector3(1.5, 2.6, -1.0)])
	await step(1)
	player.global_position = Vector3(0.0, 1.4, 0.0)
	player.velocity = Vector3(0.0, 0.0, -3.0)
	player.enter_interest_line(bar)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.SWING, "the bar did not catch the body")

# --- ZipLine -----------------------------------------------------------------------

## A straight cable down -X..., well away from the body.
func _cable() -> InterestLine:
	return _line(InterestLine.Kind.ZIPLINE, [Vector3(20.0, 12.0, 0.0), Vector3(20.0, 8.0, -30.0)])

func _ride(player: Player, cable: InterestLine, at: Vector3) -> ZiplineMove:
	var ride: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	ride.zip_line = cable
	player.global_position = at - Vector3.UP * 0.9
	player.velocity = Vector3.ZERO
	player.move_manager.set_move(Move.ZIPLINE)
	return ride

## [ME:CONFIRMED emulated N5 §17] From rest the step along the cable is
## MinZipVelocity * dt, aimed along the chord; the flying physics then decays
## it (0.015 and 0.15 per second) and adds max(MinZipAcceleration,
## |GravityZ * slope|) * dt.
func test_the_ride_steps_along_the_chord_and_flies_it() -> void:
	var player: Player = await _start()
	var cable: InterestLine = _cable()
	await step(1)
	var along: Vector3 = (Vector3(20.0, 8.0, -30.0) - Vector3(20.0, 12.0, 0.0)).normalized()
	_ride(player, cable, Vector3(20.0, 12.0, 0.0) + along * 5.0)
	await step(1)
	var accel: float = maxf(4.0, absf(player.gravity_z() * along.y))
	var expected: float = 3.0 * (1.0 - DT * 0.15 * 0.1) * (1.0 - DT * 0.15) + accel * DT
	assert_almost_eq(player.velocity.length(), expected, 2e-3)
	assert_gt(player.velocity.normalized().dot(along), 0.999, "the ride left the cable's line")

## [ME:CONFIRMED decompile] Past the last point is a fall, and StopMove counts
## that fall from 80 uu below where the hands let go.
func test_running_off_the_end_is_a_fall_counted_from_80_uu_down() -> void:
	var player: Player = await _start()
	var cable: InterestLine = _cable()
	await step(1)
	_ride(player, cable, Vector3(20.0, 8.0, -30.0))
	var y: float = player.global_position.y
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING)
	assert_almost_eq(player.enter_falling_height, y - 0.8, 0.05)

## [ME:CONFIRMED decompile] IntoZipLine is never reached from Walking, Crouch
## or Slide, nor facing against the cable's direction.
func test_the_reach_refuses_the_ground_and_the_wrong_way() -> void:
	var player: Player = await _start()
	var cable: InterestLine = _cable()
	await step(1)
	var reach: IntoZiplineMove = player.move_manager.move_for(Move.INTO_ZIPLINE)
	reach.zip_line = cable
	assert_false(reach.can_do_move(), "a reach from Walking")
	player.move_manager.set_move(Move.FALLING)
	player.rotation.y = 0.0
	player.pawn_yaw = player.rotation.y
	assert_true(reach.can_do_move(), "test setup: facing down the cable, falling")
	player.rotation.y = PI
	player.pawn_yaw = player.rotation.y
	assert_false(reach.can_do_move(), "a reach facing against the cable")

# --- melee -------------------------------------------------------------------------

func _frames_until(player: Player, move: StringName, limit: int) -> int:
	for i in limit:
		if player.move_manager.current_name == move:
			return i
		await step(1)
	return -1

## [ME:CONFIRMED anims, script] The punch is MeleeStart at 1.5x then, with no
## target, the miss at 1.5x -- 0.111 + 0.378 s -- then Walking.
func test_a_punch_lasts_its_two_animations() -> void:
	var player: Player = await _start()
	var input: ScriptedInputSource = _world["input"]
	input.press_melee()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.MELEE)
	var frames: int = await _frames_until(player, Move.WALKING, 60)
	var seconds: float = (frames + 1) * DT
	assert_true(seconds > 0.48 and seconds < 0.54, "the punch lasted %.3f s" % seconds)

## [ME:CONFIRMED decompile] A queued punch re-runs StartMove, which zeroes the
## combo counters, and is then counted down to -1: two presses in one window
## throw two punches, not three.
func test_two_queued_presses_throw_only_one_more_punch() -> void:
	var player: Player = await _start()
	var input: ScriptedInputSource = _world["input"]
	input.press_melee()
	await step(3)
	input.press_melee()
	await step(3)
	input.press_melee()
	await step(1)
	var frames: int = await _frames_until(player, Move.WALKING, 120)
	var seconds: float = (frames + 7) * DT
	assert_true(seconds > 0.9 and seconds < 1.1, "the combo lasted %.3f s" % seconds)

## [ME:CONFIRMED decompile] No air kick in the jump's first 0.1 s.
func test_no_air_kick_in_the_first_tenth_of_a_jump() -> void:
	var player: Player = await _start()
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(2)
	input.release_jump()
	input.press_melee()
	await step(1)
	assert_ne(player.move_manager.current_name, Move.MELEE_AIR)

## [ME:CONFIRMED decompile] A kick at under 200 uu/s across the ground is
## MAT_FromJumpStill, which zeroes the vertical speed as it starts.
func test_a_still_air_kick_stops_the_rise() -> void:
	var player: Player = await _start()
	var input: ScriptedInputSource = _world["input"]
	var at_entry: Array = []
	player.move_manager.move_changed.connect(func(_from: StringName, to: StringName) -> void:
		if to == Move.MELEE_AIR:
			at_entry.append(player.velocity.y))
	input.press_jump()
	await step(10)
	input.release_jump()
	input.press_melee()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.MELEE_AIR)
	assert_eq(at_entry, [0.0])

## [ME:CONFIRMED decompile TdMove_MeleeAir.Landed] A kick at speed that lands
## below the hard-landing height calls TdMove.Landed FIRST: the landing goes
## through Landing (and its SubtractLandingSpeed, which names MeleeAir) into
## Walking -- not straight to Walking.
func test_a_running_air_kick_lands_through_landing() -> void:
	var player: Player = await _start()
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	await step(40)
	input.press_jump()
	await step(30)
	input.release_jump()
	input.press_melee()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.MELEE_AIR)
	var changes: Array = []
	player.move_manager.move_changed.connect(func(from: StringName, to: StringName) -> void:
		changes.append([from, to]))
	await _frames_until(player, Move.WALKING, 60)
	assert_eq(changes.slice(0, 2), [[Move.MELEE_AIR, Move.LANDING], [Move.LANDING, Move.WALKING]])

# --- Barge -------------------------------------------------------------------------

## [ME:CONFIRMED decompile TdPlayerMoveManager] Melee on the ground asks Barge
## first; with an interactable within 90 uu ahead and no run-up it is the
## standing kick: move input off for 0.6 s, Walking at the end of
## MeleeKickObject (0.867 s).
func test_melee_at_a_door_is_a_kick() -> void:
	var player: Player = await _start()
	var door: StaticBody3D = _box(Vector3(2.0, 2.0, 0.5), Vector3(0.0, 1.0, -1.05))
	door.add_to_group(BargeMove.INTERACTABLE_GROUP)
	# A body added to the space costs the walker its floor for a frame; let it
	# land again.
	await step(15)
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: not standing")
	var input: ScriptedInputSource = _world["input"]
	input.press_melee()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.BARGE)
	assert_true(player.ignore_move_input, "the kick left the legs free")
	var frames: int = await _frames_until(player, Move.WALKING, 90)
	var seconds: float = (frames + 1) * DT
	assert_true(seconds > 0.85 and seconds < 0.9, "the kick lasted %.3f s" % seconds)

func test_melee_with_nothing_to_barge_is_a_punch() -> void:
	var player: Player = await _start()
	_box(Vector3(2.0, 2.0, 0.5), Vector3(0.0, 1.0, -1.05))
	await step(15)
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: not standing")
	var input: ScriptedInputSource = _world["input"]
	input.press_melee()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.MELEE)

# --- Interact ----------------------------------------------------------------------

## [ME:CONFIRMED decompile TdMove_Interact] The body walks to 48 uu out from
## the button, presses it, the event fires 0.6 s after arriving, and 0.85 s
## after arriving it is Walking.
func test_a_button_is_walked_to_pressed_and_used() -> void:
	var player: Player = await _start()
	var zone := UseZone.new()
	zone.interact_type = UseZone.InteractType.BUTTON
	get_tree().root.add_child(zone)
	_extra.append(zone)
	zone.global_position = Vector3(0.0, 1.0, -1.5)
	# The zone's +X out from the button, toward the body.
	zone.rotation.y = -PI / 2.0
	await step(1)
	var used: Array = []
	zone.used.connect(func() -> void: used.append(player.world_time))
	assert_true(player.use_trigger(zone), "the press was refused")
	assert_eq(player.move_manager.current_name, Move.INTERACT)
	await _frames_until(player, Move.WALKING, 120)
	assert_eq(used.size(), 1, "the button's event did not fire once")
	var spot := Vector2(player.global_position.x, player.global_position.z)
	assert_true(spot.is_equal_approx(Vector2(0.0, -1.02)), "the body stands at %s" % spot)

func test_a_button_behind_the_body_is_not_pressed() -> void:
	var player: Player = await _start()
	var zone := UseZone.new()
	zone.interact_type = UseZone.InteractType.BUTTON
	zone.angle_limit = 90.0
	get_tree().root.add_child(zone)
	_extra.append(zone)
	zone.global_position = Vector3(0.0, 1.0, 1.5)
	zone.rotation.y = PI / 2.0
	await step(1)
	assert_false(player.use_trigger(zone))
	assert_eq(player.move_manager.current_name, Move.WALKING)

## A BreakableGlass pane, an AnimatableBody3D across -Z at z = `z`.
func _glass(z: float) -> BreakableGlass:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_extra.append(holder)
	var pane := AnimatableBody3D.new()
	pane.name = "Pane"
	pane.position = Vector3(0.0, 1.0, z)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 0.05)
	mesh.mesh = box
	pane.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	pane.add_child(collision)
	holder.add_child(pane)
	var glass := BreakableGlass.new()
	glass.pane = NodePath("../Pane")
	holder.add_child(glass)
	return glass

## [ME:CONFIRMED decompile TdMove_Barge] The standing kick deals the barge on
## MeleeKickObject's BargeHitNotify, 0.33 s in, and not before.
func test_the_kick_breaks_a_pane_on_its_notify() -> void:
	var player: Player = await _start()
	var glass := _glass(-0.9)
	await step(15)
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: not standing")
	var input: ScriptedInputSource = _world["input"]
	input.press_melee()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.BARGE, "test setup: no kick")
	await step(15)
	assert_false(glass.is_broken(), "the pane broke before the kick's notify")
	await step(10)
	assert_true(glass.is_broken(), "the kick did not break the pane")

## [ME:CONFIRMED decompile TdMove_Barge] The shoulder at a run deals the barge
## on the first thing it meets; running into a pane without one is stopped.
func test_the_shoulder_breaks_a_pane_and_a_run_does_not() -> void:
	var player: Player = await _start()
	var glass := _glass(-6.0)
	await step(15)
	var input: ScriptedInputSource = _world["input"]
	input.hold_move(0.0, 1.0)
	for i in 120:
		await step(1)
		if player.global_position.z < -5.0:
			break
	await step(30)
	assert_false(glass.is_broken(), "a run broke the pane")
	assert_gt(player.global_position.z, -6.0, "the run went through the pane")
	input.hold_move(0.0, 0.0)
	await step(20)
	player.global_position.z = -3.5
	input.hold_move(0.0, 1.0)
	var barged := false
	for i in 120:
		if not barged and player.global_position.z < -4.8:
			input.press_melee()
			barged = true
		await step(1)
		if glass.is_broken():
			break
	assert_true(glass.is_broken(), "the shoulder did not break the pane")

## [ME:CONFIRMED decompile TdMove_MeleeAir.Bump] The flying kick breaks what
## it runs into: Bump, which MoveActor raises on anything but the level's own
## geometry.
func test_the_flying_kick_breaks_a_pane_it_bumps() -> void:
	var player: Player = await _start()
	var glass := _glass(-0.8)
	await step(15)
	player.global_position.y += 0.3
	player.velocity = Vector3(0.0, 0.0, -5.0)
	var kick: MeleeAirMove = player.move_manager.move_for(Move.MELEE_AIR)
	kick.melee_type = MeleeAirMove.MAT_FROM_JUMP
	player.move_manager.start(Move.MELEE_AIR)
	for i in 30:
		await step(1)
		if glass.is_broken():
			break
	assert_true(glass.is_broken(), "the flying kick did not break the pane it hit")

## [ME:CONFIRMED decompile TdMove_ZipLine.HitWall] A floor-ish face met on the
## ride is a stumble struck from 10 uu back along the ride.
func test_the_ride_meeting_a_floor_stumbles_from_behind_the_ride() -> void:
	var player: Player = await _start()
	var cable: InterestLine = _cable()
	await step(1)
	var along: Vector3 = (Vector3(20.0, 8.0, -30.0) - Vector3(20.0, 12.0, 0.0)).normalized()
	var ride: ZiplineMove = _ride(player, cable, Vector3(20.0, 12.0, 0.0) + along * 5.0)
	player.velocity = along * 6.0
	var at: Vector3 = player.global_position
	ride.hit_wall(Vector3.UP, null)
	# With no damage type recorded the stumble has no animation and hands
	# straight on to Walking, as the original's does; what it was told stays.
	assert_ne(player.move_manager.current_name, Move.ZIPLINE, "test setup: the ride went on")
	var stumble: StumbleMove = player.move_manager.move_for(Move.STUMBLE)
	var back: Vector3 = stumble.instigator_location - at
	assert_almost_eq(back.length(), 0.1, 0.001, "the instigator is not 10 uu off")
	assert_gt(back.normalized().dot(-along), 0.999, "the instigator is not behind the ride")

## [ME:CONFIRMED decompile] bDisableFaceRotation on ZipLine, Interact, Barge
## (AirBarge inherits it) and MeleeVault: the pawn does not follow the view.
func test_the_moves_that_hold_the_pawns_facing_say_so() -> void:
	var player: Player = await _start()
	for name in [Move.ZIPLINE, Move.INTERACT, Move.BARGE, Move.AIR_BARGE, Move.MELEE_VAULT]:
		assert_true(player.move_manager.move_for(name).disable_face_rotation,
			"%s lets the pawn follow the view" % name)
