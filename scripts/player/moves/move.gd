class_name Move
extends Node

# One movement action -- the Godot counterpart of the original's TdMove.
#
# [ME:CONFIRMED decompile 15.3, 15.8] The original's moves do not decide their
# own transitions in one place. Three channels change the move:
#   * an ACTION (jump, crouch, turn...): TdPlayerMoveManager.HandleMoveAction
#     asks the current move first, then walks a fixed table of candidates and
#     takes the first whose CanDoMove() is true. See MoveManager.
#   * an AUTOMATIC transition asked natively every physics tick, before the
#     physics: check_auto_moves(), then pre_physics(). Only TdPhysicsMove
#     subclasses have any (PhysicsMove).
#   * a PHYSICS EVENT: landed(), hit_wall(), reached_precise_location().
#
# Moves ported from the original answer is_ported() true and do no physics of
# their own: PawnPhysics moves the body. Moves not yet ported still run their
# own physics_update(), whose returned name the manager turns into a
# set_move(); they keep working through the same manager until they are
# rewritten from the original.
#
# Names live here rather than on Player. GDScript resolves class_name globals
# at parse time, so if the moves referenced Player.FALLING while Player
# referenced WalkingMove, the two scripts would form a cycle and fail to
# resolve. Keeping the names on this layer makes the dependency
# one-directional: Player -> moves -> Move.

## Returned from physics_update to stay in the current move.
const KEEP: StringName = &""

## 1 uu = 1 cm.
const UU := 0.01

const WALKING: StringName = &"Walking"
const FALLING: StringName = &"Falling"
const FALL_UNCONTROLLED: StringName = &"FallUncontrolled"
const SOFT_LANDING: StringName = &"SoftLanding"
const JUMP: StringName = &"Jump"
const LANDING: StringName = &"Landing"
const LAY_ON_GROUND: StringName = &"LayOnGround"
const SKILL_ROLL: StringName = &"SkillRoll"
const COIL: StringName = &"Coil"
const SLIDE: StringName = &"Slide"
## The original's TdMove_RumpSlide.
const RAMP_SLIDE: StringName = &"RampSlide"
const CROUCH: StringName = &"Crouch"
const SPEED_VAULT: StringName = &"SpeedVault"
const INTO_GRAB: StringName = &"IntoGrab"
const GRAB: StringName = &"Grab"
const WALL_RUN: StringName = &"WallRun"
const WALL_CLIMB: StringName = &"WallClimb"
const TURN_180: StringName = &"Turn180"
const TURN_180_IN_AIR: StringName = &"Turn180InAir"
const ZIPLINE: StringName = &"Zipline"
const SWING: StringName = &"Swing"
const LADDER: StringName = &"Ladder"
const BALANCE: StringName = &"Balance"
const LEDGE_WALK: StringName = &"LedgeWalk"
const SPRING_BOARD: StringName = &"SpringBoard"
const DODGE_JUMP: StringName = &"DodgeJump"

# The original's moves this project has no counterpart for yet. The action
# table names them, so they have names; nothing registers them, so
# MoveManager.can_do() is false for every one of them and the table falls
# through to the next candidate exactly as the original does when CanDoMove()
# says no.
const VERTIGO: StringName = &"Vertigo"
const BARGE: StringName = &"Barge"
const AIR_BARGE: StringName = &"AirBarge"
const MELEE: StringName = &"Melee"
const MELEE_AIR: StringName = &"MeleeAir"
const MELEE_SLIDE: StringName = &"MeleeSlide"
const MELEE_CROUCH: StringName = &"MeleeCrouch"
const MELEE_WALLRUN: StringName = &"MeleeWallrun"
const SNATCH: StringName = &"Snatch"
const STUMBLE: StringName = &"Stumble"
const STUMBLE_HARD: StringName = &"StumbleHard"
## [ME:CONFIRMED decompile] TdMove_WallKick.CanDoMove() returns false
## unconditionally: unreachable in the shipped game, and left unregistered.
const WALL_KICK: StringName = &"WallKick"
const WALLRUN_JUMP: StringName = &"WallRunJump"
const WALLRUN_DODGE_JUMP: StringName = &"WallRunDodgeJump"
const WALLCLIMB_DODGE_JUMP: StringName = &"WallClimbDodgeJump"
const WALLCLIMB_180_TURN_JUMP: StringName = &"WallClimb180TurnJump"
const GRAB_JUMP: StringName = &"GrabJump"
const GRAB_TRANSFER: StringName = &"GrabTransfer"
const GRAB_PULL_UP: StringName = &"GrabPullUp"
const SWING_JUMP: StringName = &"SwingJump"
const CLIMB: StringName = &"Climb"
const INTO_ZIPLINE: StringName = &"IntoZipLine"
const MELEE_VAULT: StringName = &"MeleeVault"
const MELEE_AIR_ABOVE: StringName = &"MeleeAirAbove"
const INTERACT: StringName = &"Interact"

# --- the original's enums ------------------------------------------------------

## Actor.EPhysics, the values the original uses. PHYS_KEEP is this project's
## "the move declares no physics": TdMove subclasses (Landing, Slide, Crouch,
## 180Turn) leave the pawn's physics as they found it.
const PHYS_KEEP := -1
const PHYS_NONE := 0
const PHYS_WALKING := 1
const PHYS_FALLING := 2
const PHYS_FLYING := 4
const PHYS_WALL_RUNNING := 12
const PHYS_WALL_CLIMBING := 13

## TdPawn.EMovementAction. [ME:CONFIRMED decompile 15.3]
const MA_NONE := 0
const MA_JUMP := 1
const MA_STOP_JUMP := 2
const MA_MELEE := 3
const MA_SNATCH := 4
const MA_CROUCH := 5
const MA_STOP_CROUCH := 6
const MA_CLIMB_UP := 7
const MA_CLIMB_DOWN := 8
const MA_CLIMB_UP_LONG := 9
const MA_CLIMB_DOWN_LONG := 10
const MA_ABORT := 11
const MA_SHIMMY_LEFT := 12
const MA_SHIMMY_LEFT_LONG := 13
const MA_SHIMMY_RIGHT := 14
const MA_SHIMMY_RIGHT_LONG := 15
const MA_TURN := 16
const MA_STUMBLE := 17
const MA_STUMBLE_HARD := 18

## TdPawn.EMoveActionHint. [ME:CONFIRMED decompile 15.8]
const MAH_NONE := 0
const MAH_LEFT := 1
const MAH_RIGHT := 2
const MAH_UP := 3
const MAH_DOWN := 4

## The controller states a move's ControllerState names. Only PlayerWalking
## computes an acceleration in this project so far.
const CS_NONE: StringName = &""
const CS_PLAYER_WALKING: StringName = &"PlayerWalking"
const CS_PLAYER_GRABBING: StringName = &"PlayerGrabbing"
const CS_PLAYER_WALL_WALKING: StringName = &"PlayerWallWalking"
const CS_PLAYER_DYING: StringName = &"PlayerDying"
const CS_PLAYER_BALANCE_WALK: StringName = &"PlayerBalanceWalk"
const CS_PLAYER_LEDGE_WALKING: StringName = &"PlayerLedgeWalking"

## Set by Player before the manager starts. Untyped for the same reason the
## names live here: a typed reference would reintroduce the cycle.
var player

## The whole config tree, for the Pawn-wide values every move needs.
var config: MovementConfig

## This move's OWN declared parameters. Assigned by Player at registration
## from the matching MovementConfig field.
var cfg: MoveConfig

## The name this move is registered under. Assigned by MoveManager.register().
var move_name: StringName = &""

# --- the original's per-move state (TdMove) -------------------------------------

## TdPhysicsMove.PawnPhysics, set by subclasses in _init(). Applied when the
## move starts, if the pawn is not already in it.
var pawn_physics: int = PHYS_KEEP
## TdPhysicsMove.ControllerState. Applied when the move starts; StopMove hands
## the controller back to PlayerWalking.
var controller_state: StringName = CS_NONE
## TdMove.DisableMovementTime / DisableLookTime: 0 nothing, < 0 until the
## move stops, > 0 that many seconds.
var disable_movement_time: float = 0.0
var disable_look_time: float = 0.0
## TdMove.bAvoidLedges, read by the walking physics' ledge check.
var avoid_ledges: bool = true

## Seconds since StartMove. [ME:CONFIRMED decompile 15.8] advanced in
## tick_move(), after the physics, so a move started this frame reads 0 in its
## first check_auto_moves() and pre_physics().
var move_active_time: float = 0.0
## TdMove.LastStopMoveTime, in Player.world_time. The original's default is
## -10, and CanDoMove only enforces RedoMoveTime when this is above zero.
var last_stop_move_time: float = -10.0
## TdMove.Timer: SetTimer(t) arms it, tick_move() counts it down and calls
## on_timer(). After the physics.
var timer: float = 0.0
## SetMoveTimer's Actor timers: counted before the physics. Each entry is
## [seconds left, interval or 0, callable].
var _move_timers: Array = []

## TdMove precise location: bUsePreciseLocation, its mode, target and speed.
var use_precise_location: bool = false
var reached_precise_location_flag: bool = false
var precise_location: Vector3 = Vector3.ZERO
var precise_location_speed: float = 4.0
var precise_location_mode: int = 0
## TdMove precise rotation: bUsePreciseRotation, the yaw it turns the body to
## and the seconds it has left to get there.
var use_precise_rotation: bool = false
var reached_precise_rotation_flag: bool = false
var precise_rotation_yaw: float = 0.0
var precise_rotation_time: float = 0.0
## Set while one of the two has arrived and the other has not; the
## ...LocationAndRotation event waits for both.
var _precise_pair_waiting: bool = false

## TdMove's look-at and camera-reset state, read by update_view_rotation().
var look_at_target_location_active: bool = false
var look_at_target_angle_active: bool = false
var look_at_interpolation_time: float = 0.0
var look_at_duration: float = -1.0
var look_at_target_location: Vector3 = Vector3.ZERO
## (yaw, pitch), radians, Godot's sense.
var look_at_target_angle: Vector2 = Vector2.ZERO
var reset_camera_look_active: bool = false
var cancel_reset_camera_look_time: float = 0.0

## Whether this move is a port of the original's logic: the manager drives the
## body through PawnPhysics instead of calling physics_update().
func is_ported() -> bool:
	return false

## The MoveConfig in force RIGHT NOW. Overridable so a move whose own config
## legitimately varies mid-move (without a state transition) has somewhere to
## express that.
func current_config() -> MoveConfig:
	return cfg

# --- lifecycle ------------------------------------------------------------------

## TdMove.CanDoMove for a move that has not been ported: the manager's own
## cooldown and the level's status blocks, which is what these moves answered
## before the action table existed. Ported moves override this with their
## original's CanDoMove, built on td_can_do_move().
func can_do_move() -> bool:
	if player.is_dying():
		return false
	return player.move_manager.can_enter(move_name)

## TdMove.CanDoMove itself: RedoMoveTime from LastStopMoveTime, never while
## dying. A level's status block is this project's addition and is asked here
## so no ported move can forget it.
func td_can_do_move() -> bool:
	if player == null:
		return false
	var redo: float = cfg.redo_move_time if cfg != null else 0.0
	if last_stop_move_time > 0.0 and redo > player.world_time - last_stop_move_time:
		return false
	if player.is_dying():
		return false
	if player.statuses != null and player.statuses.is_move_blocked(move_name):
		return false
	return true

## TdMove.CanStopMove.
func can_stop_move() -> bool:
	return true

## The common half of TdMove.StartMove and TdPhysicsMove.StartMove. Run by the
## manager before enter(), for every move.
func begin_move() -> void:
	move_active_time = 0.0
	if player == null:
		return
	player.set_ignore_move_input(disable_movement_time)
	player.set_ignore_look_input(disable_look_time)
	if pawn_physics != PHYS_KEEP and player.physics != pawn_physics:
		player.set_physics(pawn_physics)
	if controller_state != CS_NONE:
		player.controller_state = controller_state

## The common half of TdMove.StopMove and TdPhysicsMove.StopMove. Run by the
## manager after exit(), for every move.
func end_move() -> void:
	timer = 0.0
	_move_timers.clear()
	use_precise_location = false
	use_precise_rotation = false
	_precise_pair_waiting = false
	abort_look_at_target()
	reset_camera_look_active = false
	if player == null:
		return
	player.stop_ignore_move_input()
	player.stop_ignore_look_input()
	last_stop_move_time = player.world_time
	if controller_state != CS_NONE:
		player.controller_state = CS_PLAYER_WALKING

## TdMove.StartMove's own part: what the move does on entry. `previous` is the
## move that was current, which is also player.old_movement_state.
func enter(_previous: StringName) -> void:
	pass

## Returns the name of the move to switch to, or KEEP to stay. Only called on
## moves that are not ported.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

## TdMove.StopMove's own part.
func exit() -> void:
	pass

## TdMove.PostStopMove: after OldMovementState and MovementState have moved on.
func post_exit() -> void:
	pass

## TdMove.HandleMoveAction: the current move sees every action before the
## table does. A move that has not been ported keeps this project's turn
## arbitration, since its own Q handling has not been rewritten yet.
func handle_move_action(action: int) -> void:
	if action == MA_TURN and not is_ported() and player != null:
		player.move_manager.legacy_turn()

## TdMove.Landed: [ME:CONFIRMED decompile 15.7] every move that does not
## override it hands the landing to Landing, if Landing will take it.
func landed(_normal: Vector3) -> void:
	if player.move_manager.can_do(LANDING):
		player.move_manager.set_move(LANDING)

## TdMove.HitWall. Empty in the original's base.
func hit_wall(_normal: Vector3, _collider: Object) -> void:
	pass

## TdMove.ReachedPreciseLocation. Empty in the original's base.
func reached_precise_location() -> void:
	pass

## Native slot 0x124. Empty for TdMove; PhysicsMove overrides it.
func check_auto_moves() -> void:
	pass

## Native slot 0x118, TdMove's version: precise location, precise rotation,
## then the events they raise. [ME:CONFIRMED decompile N4 §2.7, 0x011fce10]
func pre_physics(delta: float) -> void:
	if use_precise_location and not reached_precise_location_flag:
		_precise_location_step(delta)
	if use_precise_rotation and not reached_precise_rotation_flag:
		_precise_rotation_step(delta)
	_precise_events()

## TdMove.EPreciseLocationMode.
const PLM_FLY := 0
const PLM_WALK := 1
const PLM_JUMP := 2
const PLM_SIM_JUMP := 3
const PLM_FALL := 4

## PLM_Jump's rise cap when the target is straight overhead: 640 uu/s.
const PLM_JUMP_OVERHEAD_SPEED := 640.0 * UU

## One frame of the precise location. Within 2 uu (2D for PLM_Walk) the
## location is reached and the velocity is left as it is; otherwise the
## velocity is aimed at it and the acceleration zeroed. Fly is 3D at
## min(distance / dt, speed); the others are horizontal at that speed, Walk
## with no vertical speed, Jump and SimJump with a vertical speed solved from
## the height left and the SCRIPT gravity. PLM_Fall is not ported: nothing
## here uses it.
func _precise_location_step(delta: float) -> void:
	var to: Vector3 = precise_location - player.global_position
	var dist3: float = to.length()
	var dist2: float = Vector2(to.x, to.z).length()
	var dist: float = dist2 if precise_location_mode == PLM_WALK else dist3
	if dist <= 2.0 * UU:
		reached_precise_location_flag = true
		return
	var dt: float = maxf(delta, 1e-6)
	match precise_location_mode:
		PLM_FLY:
			player.velocity = PawnPhysics.safe_normal(to) * minf(dist3 / dt, precise_location_speed)
		PLM_WALK:
			var h: float = minf(dist2 / dt, precise_location_speed)
			var dir: Vector3 = PawnPhysics.safe_normal_2d(to)
			player.velocity = Vector3(dir.x * h, 0.0, dir.z * h)
		PLM_JUMP:
			var h: float = minf(dist2 / dt, precise_location_speed)
			var dir: Vector3 = PawnPhysics.safe_normal_2d(to)
			var vz: float = player.velocity.y
			var dz: float = to.y
			var g: float = absf(player.gravity_z())
			if dz < 0.0:
				var a: float = -g
				if dist2 > 0.0:
					var t: float = dist2 / h
					a = (dz - t * vz) * 2.0 / (t * t)
				vz = maxf(dz / dt, a * dt + vz)
			else:
				var cap: float = PLM_JUMP_OVERHEAD_SPEED
				if dist2 > 0.0:
					cap = h / dist2 * dz * 2.0
				vz = minf(dz / dt, cap)
			player.velocity = Vector3(dir.x * h, vz, dir.z * h)
		PLM_SIM_JUMP:
			var h: float = minf(dist2 / dt, precise_location_speed)
			var dir: Vector3 = PawnPhysics.safe_normal_2d(to)
			var vz: float = player.velocity.y
			var dz: float = to.y
			var g: float = absf(player.gravity_z())
			var t: float = dist2 / h if h > 0.0 else 0.0
			if t <= delta:
				if dz <= 0.0:
					vz = maxf(dz / dt, vz - g * delta)
				else:
					vz = minf(dz / dt, 2.0 * sqrt(dz / g) * g)
			else:
				vz = dz / t + t * g * 0.5
			player.velocity = Vector3(dir.x * h, vz, dir.z * h)
	player.acceleration = Vector3.ZERO

## One frame of the precise rotation: the yaw covers the angle left in
## proportion to the time left, and lands on the target when the time runs
## out. It turns the body, which is the view here as well as the pawn.
func _precise_rotation_step(delta: float) -> void:
	var yaw: float = player.rotation.y
	if precise_rotation_time <= delta:
		yaw = precise_rotation_yaw
		reached_precise_rotation_flag = true
	else:
		yaw += wrapf(precise_rotation_yaw - yaw, -PI, PI) * (delta / precise_rotation_time)
		precise_rotation_time -= delta
	player.rotation.y = yaw

## The reached events, in the native's order. When both halves arrive on one
## frame, ReachedPreciseLocationAndRotation fires TWICE -- once from each
## half's test. The original's, kept.
func _precise_events() -> void:
	var both := false
	if reached_precise_location_flag and use_precise_location:
		use_precise_location = false
		reached_precise_location()
		if not use_precise_rotation or reached_precise_rotation_flag:
			both = true
			if not _precise_pair_waiting:
				reached_precise_location_and_rotation()
		else:
			_precise_pair_waiting = true
	if reached_precise_rotation_flag and use_precise_rotation:
		use_precise_rotation = false
		reached_precise_rotation()
		if not use_precise_location or reached_precise_location_flag:
			both = true
			if not _precise_pair_waiting:
				reached_precise_location_and_rotation()
		else:
			_precise_pair_waiting = true
	if _precise_pair_waiting and both:
		_precise_pair_waiting = false
		reached_precise_location_and_rotation()

## TdMove.SetPreciseLocation. `speed` < 0 takes GroundSpeed.
func set_precise_location(location: Vector3, speed: float = -1.0, mode: int = PLM_FLY) -> void:
	precise_location_speed = config.pawn.ground_speed if speed < 0.0 else speed
	precise_location_mode = mode
	precise_location = location
	use_precise_location = true
	reached_precise_location_flag = false

## TdMove.SetPreciseRotation, yaw only: every caller here turns the body
## about the vertical.
func set_precise_rotation(yaw: float, seconds: float) -> void:
	precise_rotation_yaw = yaw
	precise_rotation_time = seconds
	use_precise_rotation = true
	reached_precise_rotation_flag = false

## TdMove.ReachedPreciseRotation / ReachedPreciseLocationAndRotation. Empty in
## the original's base.
func reached_precise_rotation() -> void:
	pass

func reached_precise_location_and_rotation() -> void:
	pass

# --- the view (TdMove.UpdateViewRotation) ---------------------------------------
#
# [ME:CONFIRMED decompile TdMove.UpdateViewRotation] The look-at and the camera
# reset a move asks for, applied every frame after the look input. The clamp
# half of the original's function is CameraRig's (set_look_constraint).

## TdMove.SetLookAtTargetLocation: the view is pulled toward `target` by
## min(1, dt / interpolation) of the angle left, every frame, for `duration`
## seconds of this move (-1: until aborted or the move stops).
func set_look_at_target_location(target: Vector3, interpolation: float, duration: float = -1.0) -> void:
	look_at_target_location_active = true
	look_at_interpolation_time = interpolation
	look_at_duration = duration if duration == -1.0 else move_active_time + duration
	look_at_target_location = target

## TdMove.SetLookAtTargetAngle, the same pull toward a fixed (yaw, pitch).
func set_look_at_target_angle(yaw: float, pitch: float, interpolation: float, duration: float = -1.0) -> void:
	look_at_target_angle_active = true
	look_at_interpolation_time = interpolation
	look_at_duration = duration if duration == -1.0 else move_active_time + duration
	look_at_target_angle = Vector2(yaw, pitch)

func abort_look_at_target() -> void:
	look_at_target_location_active = false
	look_at_target_angle_active = false
	look_at_duration = -1.0

## TdMove.ResetCameraLook: the view is brought level, and to the pawn's yaw,
## over `interpolation` seconds, then the pitch is set to exactly zero. The
## pawn's yaw IS the view's here, so only the pitch has anywhere to go.
func reset_camera_look(interpolation: float) -> void:
	reset_camera_look_active = true
	cancel_reset_camera_look_time = player.world_time + interpolation

## Run by Player once per frame on the current move, after the look input.
func update_view_rotation(delta: float) -> void:
	var rig = player.camera_rig
	if rig == null or delta <= 0.0:
		return
	if look_at_target_location_active or look_at_target_angle_active:
		if look_at_duration == -1.0 or look_at_duration >= move_active_time:
			var wanted: Vector2 = look_at_target_angle
			if look_at_target_location_active:
				var d: Vector3 = look_at_target_location - rig.global_position
				wanted = Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
			var k: float = minf(1.0, delta / maxf(look_at_interpolation_time, 1e-6))
			rig.steer_view(wrapf(wanted.x - player.rotation.y, -PI, PI) * k,
				wrapf(wanted.y - rig.view_pitch(), -PI, PI) * k, player)
		else:
			abort_look_at_target()
	if reset_camera_look_active:
		if cancel_reset_camera_look_time > player.world_time:
			var left: float = (cancel_reset_camera_look_time - player.world_time) / delta
			rig.steer_view(0.0, -rig.view_pitch() / maxf(1.0, left), player)
		else:
			rig.steer_view(0.0, -rig.view_pitch(), player)
			reset_camera_look_active = false

## Native slot 0x11c: TdMove.TickMove. After the physics.
func tick_move(delta: float) -> void:
	if timer > 0.0:
		timer -= delta
		if timer <= 0.0:
			timer = 0.0
			on_timer()
	move_active_time += delta

## TdMove.SetTimer: a positive time arms the move's own timer; anything else
## fires on_timer() at once.
func set_timer(seconds: float) -> void:
	if seconds > 0.0:
		timer = seconds
	else:
		on_timer()
		timer = 0.0

func on_timer() -> void:
	pass

## TdMove.SetMoveTimer: an Actor timer, counted before the physics and cleared
## by StopMove.
func set_move_timer(seconds: float, looping: bool, callback: Callable) -> void:
	for entry in _move_timers:
		if entry[2] == callback:
			entry[0] = seconds
			entry[1] = seconds if looping else 0.0
			return
	_move_timers.append([seconds, seconds if looping else 0.0, callback])

func clear_move_timer(callback: Callable) -> void:
	for i in range(_move_timers.size() - 1, -1, -1):
		if _move_timers[i][2] == callback:
			_move_timers.remove_at(i)

## Counts the SetMoveTimer timers down. Called by the manager before the
## physics, the phase Actor timers run in.
func tick_move_timers(delta: float) -> void:
	var due: Array = []
	for entry in _move_timers:
		entry[0] -= delta
		if entry[0] <= 0.0:
			due.append(entry)
	for entry in due:
		if entry[1] > 0.0:
			entry[0] += entry[1]
		else:
			_move_timers.erase(entry)
		(entry[2] as Callable).call()

# --- helpers the moves not yet ported still use ---------------------------------

# --- contact drives movement --------------------------------------------------
#
# See docs/contact-drives-movement.md. The body keeps its own ballistic motion
# until a hand or a foot actually reaches the obstacle; only then does a
# scripted interaction start moving it, and only from where the body has
# actually got to.
#
# Shared here rather than written twice because the two moves that need it --
# the reach onto a ledge and the vault -- got it wrong in exactly the same way,
# and a third will be written eventually.

## Whether the obstacle a query found is close enough to be TOUCHED.
##
## DERIVED FROM THE CAPSULE, not a tunable. `face_distance` is measured from the
## body's centre, so contact is one radius away, plus a margin small enough to
## be a rounding error and large enough that a body pressed against a surface
## does not flicker in and out of touching it.
##
## A reach_distance knob can never be tuned right, because what it is trying to
## express is "how long are the arms", and that is a function of the body's own
## size. This project has been through that twice already -- see
## IntoGrabConfig.arrive_distance and WallClimbMove.rise_speed()'s base.
const CONTACT_MARGIN := 0.08

## One physics tick, for the predictive part of touching(). Read from the engine
## rather than assumed, so a project that changes its tick rate does not
## silently change how early a vault commits.
var _tick_travel: float = 1.0 / 60.0

func _ready() -> void:
	_tick_travel = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)

## AGAINST A POINT CAPTURED AT COMMIT, not against a live query.
##
## The probes are built to see an interaction COMING, and stop reporting one
## from close up: vault_query() goes invalid at about a metre out, because the
## downward anchor it plants a fixed distance ahead sails past the obstacle once
## the body is nearly on it. A move that waits for contact by asking again
## simply watches the obstacle vanish and times out. Measured directly.
##
## So the commit captures where the face IS, and the approach watches the body
## reach it. Both probes return `face_point` for this.
##
## Horizontal only: the body's own arc is still carrying it up or down, and a
## vault taken at the top of a jump is touching the face just as much as one
## taken level with it.
func touching(face_point: Vector3) -> bool:
	if face_point == Vector3.ZERO:
		return false
	# Annotated, not inferred: `player` is deliberately untyped (see above), so
	# anything read through it arrives as Variant.
	var here: Vector3 = player.global_position
	# PREDICTIVE, by one tick's travel. move_and_slide() stops the capsule at
	# exactly one radius from the face, so a test that only fires AT that radius
	# is a tick too late: at 7 m/s the body covers 0.117 m in a tick and can go
	# from clear to already-stopped between two checks, so the foot visibly
	# catches before the body is lifted -- two motions instead of one.
	#
	# Adding the distance this tick will cover means the scripted motion always
	# takes over before the collision resolves, which is what makes the vault
	# read as one continuous movement rather than a stumble and a recovery.
	return Vector2(face_point.x - here.x, face_point.z - here.z).length() <= contact_reach()

## How close the body's centre has to get to a face before the hands count as
## on it. Shared with whoever has to decide whether contact is REACHABLE at
## all, so the question "have the hands arrived" and the question "can they
## ever" cannot end up asking different distances -- which is exactly how a
## reach came to be committed at up to 0.8 m while contact needed 0.48.
func contact_reach() -> float:
	return player.current_capsule_radius() + CONTACT_MARGIN 		+ player.horizontal_speed() * _tick_travel

## Whether the hands can still arrive at `face_point`: either they are already
## within contact_reach() of it, or the body is travelling that way.
##
## ASKED TWICE, and it has to be. Before a reach is committed, because the
## approach phase moves the body not at all (docs/contact-drives-movement.md)
## and a body going nowhere near the face keeps its gap forever -- burning the
## whole max_duration, handing back, and committing again on a ledge that has
## not moved, which is a soft lock and not a flutter. And DURING the approach,
## because closing at the moment of commit does not mean still closing: a tap
## of the stick toward the wall passes the first test and has decayed to
## nothing by the next tick, which is exactly how the first version of this
## guard was got round.
func closing_on(face_point: Vector3) -> bool:
	if face_point == Vector3.ZERO:
		# touching() refuses a zero face outright, so nothing could arrive.
		return false
	var here: Vector3 = player.global_position
	var gap := Vector2(face_point.x - here.x, face_point.z - here.z)
	if gap.length() <= contact_reach():
		return true
	# Closing, however slowly. A body creeping in too slowly to arrive inside
	# max_duration still gets its one wasted reach; what this stops is the body
	# that is not approaching at all, which is the one that never stops.
	return Vector2(player.velocity.x, player.velocity.z).dot(gap) > 0.0

## Carries the body through one tick of its own ballistic motion: full gravity,
## real collisions, no scripted displacement at all.
##
## What the APPROACH phase runs. The commit has already been made and the
## animation is winding up, but nothing has been touched yet, so nothing may
## move the body except the body's own momentum. Anything else reads as the
## body being dragged through open air toward the obstacle instead of falling
## under it.
func carry_ballistically(delta: float) -> void:
	# effective_gravity(): free flight honours the player's gravity window.
	player.velocity.y -= player.effective_gravity() * delta
	player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

## ON Move RATHER THAN AirborneMove, though every other caller is one: a
## reach is a plain Move and is airborne for the whole of its approach
## phase, so it needs the same hand-off and there is nothing airborne-
## specific in here to justify a second copy.
## Carries the body through THIS tick and hands off, for the transitions that
## leave one airborne state for another. Without it the hand-off tick covers
## zero distance -- the move returns before settle_landing()'s own
## move_and_slide() -- and Player._travel_speed, which is measured from actual
## displacement, reads zero for one frame. The speed-driven FOV dips and
## springs back, which is visible as a flicker at the exact moment Jump becomes
## Falling.
##
## Landing is deliberately NOT settled here: a tick that both crosses a
## threshold and touches down is judged by the state it is handing off TO, one
## tick later. See JumpMove's own note on the descent being what the landing
## is judged on -- this survives because the fall tracker has already counted
## this tick's descent.
func advance_and_hand_off(destination: StringName) -> StringName:
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())
	return destination

## How long MoveManager refuses re-entry to this move after it leaves,
## seconds. The config's redo_move_time by default; a move overrides this
## when it can tell that THIS exit is not the kind the cooldown guards --
## LineWalkMove arms it for a fall off the line and not for a walk off its
## end (see there). Asked by MoveManager._arm_cooldown() after exit().
func redo_cooldown() -> float:
	return cfg.redo_move_time if cfg != null else 0.0

## Half-width of the look fan's YAW, radians, when the move wants something
## other than its config's min/max_look_constraint.y this tick, or NAN to
## take the config's. Asked by MoveManager._push_look_constraint() every tick,
## so a move may answer differently as its own state changes -- LedgeWalkMove
## widens the fan in third person, where the confirmed first-person number is
## not the one being looked through.
func look_yaw_half_span() -> float:
	return NAN

## Whether Q swings the view half a turn this tick. See
## MoveConfig.q_flicks_view; a move overrides this to refuse it while a script
## owns the body.
func can_flick_view() -> bool:
	return cfg != null and cfg.q_flicks_view

## The PITCH band, radians as (min, max), that replaces the move's own while
## the camera is in third person, or NANs to keep its own. The yaw half is
## untouched. Asked beside look_yaw_half_span(), for a move whose pitch limit
## is about the first-person eye -- which from outside may be the wrong limit,
## or none. MoveConfig.third_person_frees_look drops both halves outright.
func third_person_pitch_limits() -> Vector2:
	return Vector2(NAN, NAN)

# --- the environment probes the moves not yet ported answer through -------------
#
# The original asks these natively (FindAutoMoveLedge, FindWallSide, the
# IntoGrab and WallClimb CanDoMoveNative gates). Until those are ported, the
# airborne PhysicsMoves and the unported airborne moves ask this project's own
# probes, in this project's own order.

## Probes this state is allowed to run, in the original's own precedence
## order: wall, then vault, then grab. Returns a target state name, or KEEP
## when nothing fired.
func legacy_probe_transition() -> StringName:
	var c := current_config()

	# PRIORITY DECISION: wall running is checked BEFORE the ledge grab below,
	# and wins whenever both are in reach at once. This is deliberate, not an
	# accident of ordering -- ledge_query() is unconditional and was already
	# first here, so leaving the wall check after it would mean the wall check
	# could never win a single contested tick: a player flying fast along a
	# wall who clips any incidental ledge in range would always mantle
	# instead of wall-running, no matter how clearly wall running is what the
	# geometry and their speed are asking for.
	#
	# Grabbing a ledge is a RECOVERY from a misjudged jump -- something that
	# happens to you. Wall running is a ROUTE the player deliberately chose by
	# building speed and running alongside a wall; wall_running_min_speed
	# already gates it on exactly that commitment (see WallRunConfig's own
	# note: wall running CARRIES speed, it does not create it). At speed
	# beside a wall, the wall is what the player is asking for. Was decided by
	# test_a_wall_run_wins_over_a_ledge_grab_when_both_are_in_reach in
	# tests/legacy/test_wall_run.gd for the contested-geometry case -- that
	# test is ARCHIVED and NOT in the running suite, so nothing enforces this
	# today; restore the pin when the behavioural suite is rewritten.
	# [ME:CONFIRMED 04 §4.1] A wall run can only start from the ORIGINAL's Jump
	# state, never from its Falling state -- all 15 measured airborne entries
	# came from Jump. The two are separated by EnterToFallingZSpeed = -200, i.e.
	# purely by how fast you are already dropping.
	#
	# Jump and Falling are separate states (both AirborneMove subclasses), and
	# the split is expressed directly: JumpConfig sets check_for_wall_climb,
	# FallingConfig does not (see FallingConfig's own note on that absence).
	# DO NOT let Falling set it too -- any descent that so much as brushes a
	# building would convert into a wall run, a 40 m drop becoming Spider-Man
	# rather than a death.
	#
	# Measured entry window: -104 .. +510 uu/s of vertical speed, comfortably
	# inside this threshold (-2.0 m/s) at the bottom end. The TOP end is
	# deliberately unbounded: rising fast is fine to attach from, and
	# WallRunningVelocityStartLimit = 300 turned out NOT to be a ceiling on it.
	# KICKING STRAIGHT UP IS TESTED BEFORE RUNNING ALONG, and has to be: the
	# head-on band (0-33 degrees) sits INSIDE the wall run's forward band
	# (0-57), so whichever is asked first wins every head-on approach outright.
	#
	# The original has one bCheckForWallClimb flag covering both moves, which
	# means the choice is made downstream of the flag, and the angle is the
	# only thing in the data with numbers attached: 33 / 57 / 60 tile the
	# quarter-circle exactly once. Asking the narrower band first is what makes
	# that tiling real rather than decorative -- see WallClimbConfig's own note.
	#
	# This is also why the wall run's forward branch below is UNCHANGED at 57
	# rather than being narrowed to 33-57. Narrowing it would be the same
	# behaviour expressed twice, and the second copy would rot.
	# NO SPEED GATE, unlike the wall run's -- DO NOT add one. [ME:CONFIRMED]
	# Standing still, pressed against a wall, W and space climbs in the
	# original. What gates a climb instead is INTENT, which is what
	# approach_direction() carries: a body going nowhere and asking for
	# nothing returns ZERO, and a zero approach is refused below.
	if c.check_for_wall_climb and player.probes != null \
			and player.move_manager.can_enter(WALL_CLIMB):
		var heading_at: Vector3 = player.approach_direction()
		var ahead: Dictionary = Probes.NO_WALL_AHEAD if heading_at == Vector3.ZERO \
			else player.probes.wall_ahead_query(heading_at)
		if ahead["valid"] and ahead["tall_enough"] \
				and float(ahead["incidence"]) <= config.wall_climb.vertical_start_angle:
			return WALL_CLIMB

	if c.check_for_wall_climb and player.probes != null \
			and player.horizontal_speed() >= config.wall_run.wall_running_min_speed:
		var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
		var wall: Dictionary = player.probes.wall_query(heading)
		# TWO COOLDOWNS, DELIBERATELY, ANSWERING DIFFERENT QUESTIONS.
		#
		# can_enter() is [ME:CONFIRMED 04 §4.1] redo_move_time (0.15 s) and
		# is blind to WHICH wall: it is the short guard against a run
		# flickering off and back on within a few ticks. DO NOT let this
		# cooldown alone stand in for the same-wall refusal below -- on its
		# own it also blocks re-entry onto a wall the player never left, which
		# reads as the game refusing a run it should allow, while the
		# same-wall chain it is not built to catch stays reachable through it.
		#
		# The geometric rule that IS about which wall lives a few lines down,
		# in recent_wall_refuses_run(). Keeping them apart is what lets the
		# short one stay short.
		if wall["valid"] and player.move_manager.can_enter(WALL_RUN):
			var incidence: float = wall["incidence"]
			# 0-57 degrees takes the forward branch, 60+ takes the strafe
			# branch (04 §4.1); the 3-degree gap between them is a deliberate
			# hysteresis band. There is no "current branch" to hold onto
			# here -- this check only ever runs BEFORE the move exists, on a
			# player who is not yet wall running -- so landing in the gap
			# simply means neither branch qualifies THIS tick; the player
			# stays in this state and the next tick's fresh query tries again.
			var qualifies: bool = incidence <= config.wall_run.wall_running_forward_max_start_angle \
				or incidence >= config.wall_run.wall_running_strafe_start_angle
			# THE WALL YOU JUST LEFT WILL NOT TAKE YOU BACK. Kicking off a
			# wall sends the body away from it, so a second run on the same
			# side of a wall facing the same way is not a rule being enforced,
			# it is arithmetic -- see Player.recent_wall_refuses_run(). Two
			# walls facing EACH OTHER stay legal, which is the zig-zag
			# corridor, and so does a wall angled away from the one just left.
			var refused: bool = player.recent_wall_refuses_run(wall["normal"], int(wall["side"]))
			if qualifies and not refused:
				return WALL_RUN

	# Checked BEFORE the ledge grab below, mirroring 05 §5.7's own fallback
	# order: a jump that overshoots or undershoots tries the vault table
	# FIRST, and only falls through to "hang and pull up" (GrabMove, the
	# slowest path in the whole move set) once nothing in VaultTypes matches.
	# This is also where autostepuprightleg actually lives in practice: its
	# MinSpeedZ/MaxSpeedZ band (-6.0..0.0) requires already falling, which
	# WalkingMove's own grounded vault check can never see -- see
	# SpeedVaultConfig.variants' own per-field note on that row.
	if c.check_for_vault_over and player.probes != null:
		# Cleared before the question is asked: _vault_speed_z() only ever sets
		# it, so a stale true from a tick that did not go on to vault would
		# otherwise make the next vault look like a scramble.
		player.pending_vault_rescue = false
		var hit: Dictionary = player.probes.vault_query()
		if hit["valid"] and not player.recent_wall_refuses_climb_onto(hit["edge"]):
			var variant: Dictionary = config.speed_vault.pick_variant(
				hit["height"], hit["vault_over"], _vault_speed_z(),
				player.horizontal_speed())
			# ALREADY TOUCHING NEEDS NO LEAD TIME.
			#
			# should_commit() asks whether the obstacle will be reached within
			# MaxDistanceTime at the current speed -- a question about an
			# APPROACH, and one that divides by horizontal speed. A wall climb
			# has none: the climb's own friction has taken it, and the body is
			# going straight up against a surface it is already in contact with.
			# So the gate refuses every vault out of a climb, which leaves a
			# hole: a 3.5 m wall where the climb tops out with the edge 1.7 m
			# above the feet is too LOW for a grab (min_wall_height is 1.8)
			# and unreachable by a vault that will not commit -- nothing
			# fires and the player slides back down.
			#
			# Contact is the other way of satisfying the same question, and it
			# satisfies it completely. See docs/contact-drives-movement.md.
			#
			# BUT ONLY WHILE THE BODY IS STILL GOING UP. Read the paragraph
			# above again: every word of it is about a CLIMB topping out --
			# the body is going straight up against a surface it is already
			# in contact with. A body that is merely RESTING against a wall
			# satisfies touching() just as completely and is going nowhere,
			# so DO NOT drop the rising check below: without it the bypass
			# fires forever:
			#
			#   Walking -> Falling -> SpeedVault -> Walking -> Falling -> ...
			#
			# at about forty times a second, for any body at rest pressed
			# against a face at h 0.00 v 0.00 -- for example beside a block
			# after a grab, or backing slowly off a roof edge until it drops.
			# Neither case is climbing.
			#
			# THE VAULT IS NOT WHAT LOOPS. A vault fired from a standstill has
			# no speed to carry the body anywhere, so it ends where it began,
			# hands back to Walking, falls, and meets the same open bypass on
			# the next tick. Any gate that cannot be satisfied twice from the
			# same spot would do; requiring the rise is the one that gives the
			# bypass back exactly the case it was written for.
			var rising: bool = player.velocity.y > 0.0
			var closing: bool = config.speed_vault.should_commit( 				hit["distance"], player.horizontal_speed(), variant)
			# NOWHERE TO PASS THROUGH IS NOT A VAULT. Unlike a grab, which can
			# still hang on a capped ledge, a vault has no half-measure: every
			# one of them carries the body through the space above the obstacle,
			# whether it lands there or beyond. DO NOT vault into a slab over
			# the top -- the body clips straight through it.
			var room: bool = player.fits_standing_at(hit["top"])
			if room and (closing or (rising and touching(hit.get("face_point", Vector3.ZERO)))):
				player.pending_vault_variant = variant
				return SPEED_VAULT

	# Checked before this tick's own move_and_slide(), same as the vault check
	# just above: if it fires, this move hands off to GrabMove (which
	# drives the body directly, see its own note) without this tick's physics
	# ever having moved the body at all. can_enter() enforces GrabConfig's own
	# redo_move_time (0.45 s) -- it replaces Player.can_grab_ledge(), the last
	# of the three hand-rolled cooldowns Player used to carry -- so dropping
	# off a ledge cannot instantly re-grab the very same one.
	# [ME:CONFIRMED] INTO_GRAB, not GRAB. The original reaches for a ledge
	# before hanging from it (TdMove_IntoGrab), which is what carries the body
	# to the same hanging pose however it was caught. The cooldown is still
	# checked against GRAB, since that is the move being re-entered and where
	# redo_move_time lives.
	# The cable and the bar are not caught here: their volumes ask every tick
	# (Player._update_movement_volume, TdSwingVolume / TdZiplineVolume
	# PawnUpdate).
	# The ladder: an interest point the level author placed, PLUS the
	# frontal fan -- DO NOT let a ladder catch from any side but the front;
	# catch_gate() enforces it. Asked here, before ever transitioning, so
	# LadderMove.enter()'s own copy of this same check (see its note) never
	# actually fires in play.
	#
	# NO fall_limit HERE, unlike the cable and the bar above. Those two carry
	# the original's own ZVelocityFallLimit; the ladder never had one, and the
	# 6 m/s it used to borrow from them is 1.125 m of free fall at gravity 16
	# -- it refused every drop worth catching. [ME:CONFIRMED] a ladder CAN be
	# caught mid-fall, and a catch past hard_landing_height costs the same
	# lockout a hard landing does, red screen and all, rather than being
	# refused (LadderMove.enter() arms it). DO NOT restore a speed gate
	# here: the window's real ceiling is falling_uncontrolled_height, already
	# enforced by FallUncontrolledConfig leaving check_for_ladder clear, so a
	# fall that has gone uncontrolled still catches nothing.
	if c.check_for_ladder and player.move_manager.can_enter(LADDER):
		var rail: InterestLine = player.nearest_interest_line(InterestLine.Kind.LADDER)
		if rail != null and LadderMove.catch_gate(player, rail):
			return LADDER

	# A ledge, same interest-point reasoning: catch_gate() is the single
	# question every entry site asks, so jumping onto a ledge and falling
	# onto one both get answered identically to walking onto one.
	if c.check_for_ledge_walk and player.move_manager.can_enter(LEDGE_WALK):
		var ledge: InterestLine = player.nearest_interest_line(InterestLine.Kind.LEDGE_WALK)
		if ledge != null and LedgeWalkMove.catch_gate(
				player, ledge, config.ledge_walk.foot_snap_height):
			return LEDGE_WALK

	# A beam, same interest-point reasoning: catch_gate() is the single
	# question every entry site asks, so jumping onto a beam and falling onto
	# one both get answered identically to walking onto one.
	if c.check_for_balance and player.move_manager.can_enter(BALANCE):
		var beam: InterestLine = player.nearest_interest_line(InterestLine.Kind.BALANCE)
		if beam != null and BalanceMove.catch_gate(
				player, beam, config.balance.foot_snap_height):
			return BALANCE

	# The reach's own cooldown too, not only the hang's: a reach that gave up
	# hands back to a Falling whose automatic transitions run before its
	# physics, so without it the same ledge is committed to again on the next
	# tick, before the fall can land.
	if c.check_for_grab and player.probes != null and player.move_manager.can_enter(GRAB) \
			and player.move_manager.can_enter(INTO_GRAB):
		var ledge: Dictionary = player.probes.ledge_query()
		# The REACH's own range is checked here rather than inside it. Checked
		# there, a ledge that is visible but too far away sends the body into
		# IntoGrab, which gives up on its first tick and returns to Falling,
		# which sees the same ledge again -- an endless Falling/IntoGrab
		# flutter for as long as the ledge stays in view.
		# ...and it will not let you climb onto its own top either. Same
		# arithmetic as the wall-run refusal above: your legs are pushing off
		# that wall, so the body cannot be sent to the side it is on. This is
		# what stops a wall run from ending in a grab onto the very wall it
		# just left.
		var same_side: bool = ledge["valid"] \
			and player.recent_wall_refuses_climb_onto(ledge["edge"])
		if ledge["valid"] and _within_reach(ledge) and _can_close_the_gap(ledge) 				and not same_side:
			return INTO_GRAB

	return KEEP

## Whether a ledge is close enough to reach for, horizontally.
##
## [ME:CONFIRMED] ledge_find_distance is 3.5 m -- how far the probe may LOOK,
## not how far the body may be hauled. Reaching from that range reads as a
## magnet -- jump vaguely wallward and get pulled in across open air -- so
## DO NOT widen the reach to match it; the reach is held to its own, much
## shorter range. See IntoGrabConfig.max_reach_distance.
## Whether a reach at this ledge could ever make CONTACT, which is a different
## question from _within_reach() above and the one that was missing.
##
## The approach phase moves the body not at all -- it flies its own arc and the
## reach waits to see whether the hands arrive (docs/contact-drives-movement.md).
## So a body with no horizontal travel toward the face keeps exactly the gap it
## started with, and if that gap is wider than contact_reach() the hands never
## arrive: the reach burns its whole max_duration, hands back to Falling, waits
## out redo_move_time, and commits again on a ledge that has not moved. Nothing
## about the situation changes, so the loop does not end -- and the player has
## no control for the 1.5 s of each pass, which is a soft lock rather than a
## flutter.
##
## Reported at 0.8 m of commit range against 0.48 m of contact range, so any
## ledge in that band locked the player up. Standing 0.8 m out and jumping
## straight up did it; so did standing flush and looking 34 degrees off square,
## because the probe measures along the LOOK direction and turning the view
## lengthens the same gap.
##
## DO NOT fix this by shrinking max_reach_distance to the contact range. The
## wider commit is right for the case it was written for: a body flying AT a
## wall closes the gap on its own within a tick or two, and refusing it at
## 0.8 m would take away the ordinary running grab. What is wrong is committing
## when nothing will close the gap.
##
## Asked every tick rather than once at take-off, so a jump straight up
## followed by air control toward the wall still commits the moment the body
## starts going there.
func _can_close_the_gap(ledge: Dictionary) -> bool:
	return closing_on(ledge.get("face_point", Vector3.ZERO))

func _within_reach(ledge: Dictionary) -> bool:
	# Measured to the WALL, not to the edge point. `edge` is on the ledge's
	# top, found by dropping a probe past the face, so against anything with
	# depth it sits well behind the surface the body would touch -- 1.78 m for
	# a 1 m deep block whose face was only 0.9 m away.
	return float(ledge.get("face_distance", INF)) <= config.into_grab.max_reach_distance

## The vertical speed the vault table is asked about, which is the REAL one
## except inside the shin-catch window below.
##
## A DELIBERATE DIVERGENCE FROM THE ORIGINAL. [ME:CONFIRMED] Five of the six
## rows in SpeedVaultConfig.variants require MinSpeedZ >= 0 -- they only
## match while RISING -- and the sixth, auto_step_up_right_leg, is the
## descending one but tops out at 0.48 m and 3 m/s. So falling onto a
## metre-high ledge at running pace matches NOTHING in the original, and the
## only way to vault it is to catch the rising half of a jump, which leaves
## too narrow a window to use in practice.
##
## [ME:INFERRED 05 §5.7] autostepuprightleg is a RESCUE in the original, not
## a move: the player jumps a gap and falls short, their shin catches the far
## edge, and the game kicks them up in the last 0.2 s. This function widens
## that rescue rather than reproducing it, and it is worth knowing which is
## which if the two are ever compared.
##
## Three gates, so it stays a rescue rather than becoming a second way to play:
##
##   * FALLING, not rising. A rising body is already covered by the real rows.
##   * SHORT OF A HARD LANDING. hard_landing_height is the same 5.3 m that
##     decides whether a landing costs two seconds, reused rather than given a
##     knob of its own: a fall that is about to hurt is not one to rescue.
##   * ASKING FOR IT. The player has to be pushing INTO the obstacle. Falling
##     past a ledge with no input is a fall, and turning it into a vault would
##     be the game playing itself.
##
## Reported as a level speed rather than as a flag, which keeps
## SpeedVaultConfig.variants a pure transcription of the original's table: the
## high tiers ask for MinSpeedZ 0.5 and still refuse, so a genuinely high vault
## still costs a jump. Only the middle tier is rescued.
func _vault_speed_z() -> float:
	var speed_z: float = player.velocity.y
	if speed_z >= 0.0:
		return speed_z
	if player.fall_tracker == null:
		return speed_z
	if player.fall_tracker.fall_height >= config.pawn.hard_landing_height:
		return speed_z
	# player.last_input rather than a parameter: probe_transition() takes none,
	# and this is the same field CharacterAnimator reads for the same reason.
	if player.last_input == null:
		return speed_z
	var wish: Vector3 = player.wish_direction(player.last_input)
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if wish.length_squared() < 0.0001 or facing.length_squared() < 0.0001:
		return speed_z
	if wish.normalized().dot(facing.normalized()) <= 0.0:
		return speed_z
	# Recorded, because it changes what the vault LOOKS like. A rescued vault
	# was not set up -- there was no run-up and no plant, the player simply
	# arrived -- so CharacterAnimator plays a step-up rather than the
	# hand-planted SafetyVault. See SpeedVaultMove.is_scramble().
	player.pending_vault_rescue = true
	return 0.0
