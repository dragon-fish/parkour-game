class_name SwingMove
extends PhysicsMove

# The original's TdMove_Swing, ported. [ME:CONFIRMED decompile N5 §16; script
# TdMove_Swing, TdSwingVolume; natives GetPawnLocation / GetPawnAngle /
# PrePhysics / UpdateShimmy emulated]
#
# A pendulum in angle only: the pawn is TELEPORTED onto the arc every frame
# (FarMoveActor) while Velocity stays zero, so the flying physics moves
# nothing and CheckAutoMoves sees a body at rest. The angular acceleration is
# a fixed 10 sin(a) rad/s^2 -- not g / L -- with 0.8/s damping and a
# cos(a) * MaxSwingVelocity cap that makes |a| = pi/2 a hard ceiling.
#
# The bar is this project's SWING InterestLine; its volume asks for the swing
# every tick the body is inside it (volume_pawn_update(), from Player). The
# original's TdSwingVolume.Location is the bar's middle here, its Y axis the
# bar, its X axis horizontal and square to the bar.

## TdSwingVolume.bSnapToCenter has no counterpart on an InterestLine: every
## bar here behaves as the default, false.

## The original's integrator constants. [ME:CONFIRMED emulated N5 §16]
const ANGULAR_ACCELERATION := 10.0
const DAMPING := 0.8
const PUMP := 3.0
## ShimmyVelocity: 35 uu/s along the bar.
const SHIMMY_SPEED := 35.0 * UU
## The pull onto the arc ends within 2 uu.
const INTERPOLATION_DONE := 2.0 * UU
## The shimmy step is scaled by SwingStrafe's weight. [ME:INFERRED N5 §25.1]
## read as NodeTotalWeight: the strafe's own, ramping over its 0.2 s blend-in.

## TdMove_Swing.Volume: the bar, set by the volume that asked.
var volume: InterestLine = null
var swing_velocity: float = 0.0
var swing_angle: float = 0.0
var swing_direction: Vector3 = Vector3.FORWARD
var bar_direction: Vector3 = Vector3.RIGHT
var swing_location: Vector3 = Vector3.ZERO
var is_interpolating_into: bool = false
var is_shimmying: bool = false
var is_turning: bool = false
var shimmy_velocity: float = 0.0
var shimmy_time: float = 0.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_GRABBING
	# [ME:CONFIRMED decompile] DisableLookTime = -1: no look input for the
	# whole swing.
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

# --- the volume ------------------------------------------------------------------

## Volume.Location: the bar's middle.
static func volume_location(line: InterestLine) -> Vector3:
	return line.sample(line.length() * 0.5)["position"]

## The volume's Y axis: the bar, flat.
static func volume_y(line: InterestLine) -> Vector3:
	var t: Vector3 = line.sample(line.length() * 0.5)["tangent"]
	t.y = 0.0
	return t.normalized() if t.length_squared() > 1e-8 else Vector3.RIGHT

## The volume's X axis, Vector(Volume.Rotation): horizontal and square to the
## bar, with Y on its right as in the original's axes.
static func volume_x(line: InterestLine) -> Vector3:
	return Vector3.UP.cross(volume_y(line)).normalized()

## TdSwingVolume.PawnUpdate: offers the swing every tick the body is inside
## the bar's volume. Returns whether the swing took the body.
func volume_pawn_update(line: InterestLine) -> bool:
	if player.move_manager.current_name == SWING:
		return false
	volume = line
	if can_do_move():
		player.move_manager.set_move(SWING)
		return true
	volume = null
	return false

## TdMove_Swing.CanDoMove: facing the bar (cos < -0.3 between the facing and
## bar-to-pawn), moving toward it, and no more than 30 degrees above it.
func can_do_move() -> bool:
	if volume == null or not is_instance_valid(volume):
		return false
	var grip_to_pawn: Vector3 = PawnPhysics.safe_normal(player.global_position - volume_location(volume))
	if grip_to_pawn.dot(player.facing()) >= -0.3:
		return false
	if grip_to_pawn.dot(PawnPhysics.safe_normal(player.velocity)) >= 0.0:
		return false
	if grip_to_pawn.dot(Vector3.DOWN) < -0.5:
		return false
	return td_can_do_move()

# --- the pendulum (natives) ------------------------------------------------------

## GetPawnLocation: SwingLocation + L (sin a SwingDirection - cos a Up).
func get_pawn_location(angle: float) -> Vector3:
	return swing_location + cfg.pendulum_length * (sin(angle) * swing_direction - cos(angle) * Vector3.UP)

## GetPawnAngle: the exact inverse of get_pawn_location() over -pi .. pi.
func get_pawn_angle(location: Vector3) -> float:
	var d: Vector3 = location - swing_location
	var x: float = d.dot(swing_direction)
	var z: float = d.y
	var length: float = sqrt(x * x + z * z)
	if length > 0.0:
		x /= length
		z /= length
	var a: float = asin(clampf(x, -1.0, 1.0))
	if z > 0.0:
		a = PI - a
	if a > PI:
		a -= TAU
	return a

# --- StartMove / StopMove --------------------------------------------------------

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
	var origin: Vector3 = volume_location(volume)
	var vy: Vector3 = volume_y(volume)
	var vx: Vector3 = volume_x(volume)
	# PointDistToLine: the grip is the point of the bar's line nearest the pawn.
	swing_location = origin + vy * (player.global_position - origin).dot(vy)
	var to_grip: Vector3 = PawnPhysics.safe_normal(origin - player.global_position)
	if to_grip.dot(vx) >= 0.0:
		bar_direction = vy
		swing_direction = vx
	else:
		bar_direction = -vy
		swing_direction = -vx
	swing_angle = get_pawn_angle(player.global_position)
	# [ME:CONFIRMED decompile N5 §25.8] an INTEGER Clamp(int(a), int(-1.2),
	# int(-0.7)) = Clamp(trunc(a), -1, 0): the start angle is 0 or -1 rad,
	# never anything between. The 0.15 s pull onto the arc hides the jump.
	swing_angle = float(clampi(int(swing_angle), int(-1.2), int(-0.7)))
	swing_velocity = cfg.max_swing_velocity * minf(1.0, Vector2(player.velocity.x, player.velocity.z).length() / (500.0 * UU))
	set_precise_rotation(UE.dir_yaw(swing_direction), cfg.anim_blend_time)
	is_interpolating_into = true
	_set_pawn_rotation(swing_angle)
	reset_camera_look(cfg.anim_blend_time)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.anim_slot.stop(cfg.anim_blend_time)
	play_slot_anim(&"SwingHardStart", 1.0, cfg.anim_blend_time, 0.2)
	set_move_timer(cfg.anim_blend_time, false, _stop_interpolating)

func exit() -> void:
	is_shimmying = false
	is_turning = false
	player.set_swing_pitch_target(0.0)

func _stop_interpolating() -> void:
	is_interpolating_into = false

# --- the frame -------------------------------------------------------------------

## Native PrePhysics. The base TdPhysicsMove PrePhysics runs at the END.
func pre_physics(delta: float) -> void:
	if not is_interpolating_into:
		swing_velocity -= sin(swing_angle) * delta * ANGULAR_ACCELERATION
		swing_velocity -= swing_velocity * delta * DAMPING
		# Pumping: only in the direction the swing is already going.
		if not is_shimmying and not is_turning:
			if player.move_action_hint == MAH_UP and swing_velocity >= 0.0:
				swing_velocity += delta * PUMP
			if player.move_action_hint == MAH_DOWN and swing_velocity <= 0.0:
				swing_velocity -= delta * PUMP
	var a: float = swing_angle
	if a > 0.0:
		swing_velocity = minf(swing_velocity, cos(a) * cfg.max_swing_velocity)
	if a < 0.0:
		swing_velocity = maxf(swing_velocity, -cos(a) * cfg.max_swing_velocity)
	if not is_interpolating_into:
		swing_angle = clampf(swing_velocity * delta + a, -PI, PI)
	if is_turning and signf(a) != signf(swing_angle):
		on_timer()
	_update_shimmy(delta)
	var p: Vector3 = get_pawn_location(swing_angle)
	if is_interpolating_into:
		var d: Vector3 = p - player.global_position
		if d.length_squared() < INTERPOLATION_DONE * INTERPOLATION_DONE:
			is_interpolating_into = false
		else:
			# MoveActiveTime / AnimBlendTime of what is LEFT, every frame: faster
			# than linear.
			p = player.global_position + d * (move_active_time / cfg.anim_blend_time)
	player.global_position = p
	super.pre_physics(delta)

## Native UpdateShimmy.
func _update_shimmy(delta: float) -> void:
	if not is_shimmying:
		return
	var weight: float = player.anim_slot.weight_of(&"SwingStrafe") \
		if player.anim_slot.is_playing(&"SwingStrafe") else 1.0
	var step: float = weight * shimmy_velocity * delta
	if not can_shimmy(step):
		abort_shimmy()
		return
	swing_location += bar_direction * step
	shimmy_time -= delta
	if shimmy_time < 0.0:
		abort_shimmy()

## CanShimmy: the grip moved by `step` along the bar stays inside the volume.
func can_shimmy(step: float) -> bool:
	if volume == null or not is_instance_valid(volume):
		return false
	var at: Vector3 = swing_location + bar_direction * step
	var on_line: Vector3 = volume.sample(volume.closest_offset(at))["position"]
	return on_line.distance_to(at) <= volume.reach_radius

func abort_shimmy() -> void:
	player.anim_slot.stop(0.25)
	is_shimmying = false

## TickMove: the base, then SetPawnRotation.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_set_pawn_rotation(swing_angle)

## SetPawnRotation: the original rolls a SwingControl bone by the angle. Here
## the model leans by it, and the eye slides with a forward lean.
func _set_pawn_rotation(angle: float) -> void:
	player.set_swing_pitch_target(angle * cfg.model_pitch_follow)
	if player.camera_rig != null:
		var lean: float = maxf(sin(angle), 0.0)
		player.camera_rig.extra_eye_forward = lean * cfg.eye_forward_lean
		player.camera_rig.extra_eye_lift = lean * cfg.eye_lift_lean

# --- actions ---------------------------------------------------------------------

func handle_move_action(action: int) -> void:
	var move_left: bool = action == MA_SHIMMY_LEFT or action == MA_SHIMMY_LEFT_LONG
	var move_right: bool = action == MA_SHIMMY_RIGHT or action == MA_SHIMMY_RIGHT_LONG
	if action == MA_JUMP:
		var jump_angle: float = minf(PI / 2.0, swing_angle - cfg.swing_angle_timing_offset)
		if jump_angle > -PI / 4.0:
			_jump_off(jump_angle)
	elif not is_interpolating_into and action == MA_CROUCH:
		_let_go()
	elif not is_interpolating_into and not is_turning and not is_shimmying and action == MA_TURN:
		is_turning = true
	elif action == MA_MELEE:
		var jump_angle: float = minf(PI / 2.0, swing_angle - cfg.swing_angle_timing_offset)
		if jump_angle > -PI / 4.0:
			# [ME:CONFIRMED decompile] SetMove(MeleeAir, bCheckCanDo): MeleeAir
			# refuses every state but IntoGrab, Jump, Falling, WallRunJump and
			# GrabJump, so this never kicks -- and the refused check leaves
			# PendingMovementState behind (MoveManager.pawn_can_do()).
			player.move_manager.set_move(MELEE_AIR, true)
	elif not is_turning and not is_shimmying and (move_left or move_right):
		if absf(swing_velocity) < 1.0 and absf(swing_angle) < PI / 8.0:
			var dir: float = 1.0 if move_right else -1.0
			if can_shimmy(dir * UU):
				is_shimmying = true
				shimmy_velocity = SHIMMY_SPEED * dir
				play_slot_anim(&"SwingStrafe", dir, 0.2, 0.2)
				shimmy_time = absf(player.anim_slot.current_playback_length())

## OnTimer, raised natively at the zero crossing of a turn: Swing180 with root
## rotation -- which turns the PAWN, and the view's yaw with it
## (Player.turn_by_root_rotation()) -- the pawn squared to the swing, the
## pendulum stopped.
func on_timer() -> void:
	player.use_root_rotation(true)
	play_slot_anim(&"Swing180", 1.0, 0.2, 0.3, false, true)
	player.pawn_yaw = _yaw_of(swing_direction)
	swing_velocity = 0.0
	swing_angle = 0.0
	_set_pawn_rotation(swing_angle)

## OnCeaseRelevantRootMotion: the turn is over; the swing's frame flips and
## the pawn and the view are squared to it, level.
func on_cease_relevant_root_motion() -> void:
	if not is_turning:
		return
	is_turning = false
	player.use_root_rotation(false)
	swing_direction = -swing_direction
	bar_direction = -bar_direction
	player.pawn_yaw = _yaw_of(swing_direction)
	player.rotation.y = player.pawn_yaw
	if player.camera_rig != null:
		player.camera_rig.set_pitch(0.0)
	swing_velocity = 0.25

## JumpOff: to the next bar ahead if there is one, otherwise off the tangent of
## the arc at 600 cos(JumpAngle).
func _jump_off(jump_angle: float) -> void:
	var swing_jump = player.move_manager.move_for(SWING_JUMP)
	var target: InterestLine = check_for_target_volume()
	if swing_jump != null:
		swing_jump.target_volume = target
	if target == null:
		# BarDirection x Normal(SwingLocation - Location) in the original's
		# left-handed axes is the operands swapped in Godot's right-handed
		# ones: the tangent of the arc, forward and up on a forward swing.
		var n: Vector3 = PawnPhysics.safe_normal(swing_location - player.global_position)
		var velocity_direction: Vector3 = n.cross(bar_direction)
		player.velocity = velocity_direction * cos(jump_angle) * cfg.exit_velocity_modifier
		player.acceleration = player.velocity
		player.gravity_modifier = cfg.exit_gravity_modifier
		player.gravity_modifier_timer = cfg.exit_gravity_modifier_time
		play_slot_anim(&"SwingJumpOff", 1.0, 0.2, 0.2)
	player.move_manager.set_move(SWING_JUMP)

## LetGo: Falling, with the zero velocity the swing holds -- straight down.
func _let_go() -> void:
	play_slot_anim(&"SwingEnd", 1.0, 0.2, 0.2)
	player.move_manager.set_move(FALLING)

## CheckForTargetVolume: another bar ahead, within
## 100 + max(0, 500 / 4.25 * SwingVelocity) uu of the volume centre along the
## swing direction, the trace starting 100 uu out. The first one met wins.
func check_for_target_volume() -> InterestLine:
	if volume == null or not is_instance_valid(volume):
		return null
	var reach: float = (maxf(0.0, 500.0 / 4.25 * swing_velocity) + 100.0) * UU
	var origin: Vector3 = volume_location(volume)
	var from: Vector3 = origin + swing_direction * (100.0 * UU)
	var to: Vector3 = origin + swing_direction * reach
	var best: InterestLine = null
	var best_t: float = INF
	for node in player.get_tree().get_nodes_in_group("interest_lines"):
		var line := node as InterestLine
		if line == null or line == volume or line.kind != InterestLine.Kind.SWING:
			continue
		var t: float = _segment_entry(line, from, to)
		if t < best_t:
			best_t = t
			best = line
	return best

## Where along from..to (0..1) the segment first enters `line`'s volume, or INF.
static func _segment_entry(line: InterestLine, from: Vector3, to: Vector3) -> float:
	var length: float = from.distance_to(to)
	var steps: int = maxi(1, ceili(length / 0.05))
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var at: Vector3 = from.lerp(to, t)
		var on_line: Vector3 = line.sample(line.closest_offset(at))["position"]
		if on_line.distance_to(at) <= line.reach_radius:
			return t
	return INF

static func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
