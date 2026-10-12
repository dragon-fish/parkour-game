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
## TdMove_VaultOver, the vault CheckAutoMoves sets: TdMove_SpeedVault's logic
## under its own state.
const VAULT_OVER: StringName = &"VaultOver"
## TdMove_AutoStepUp (dead: its CanDoMove always refuses) and TdMove_StepUp
## (nothing sets it).
const AUTO_STEP_UP: StringName = &"AutoStepUp"
const STEP_UP: StringName = &"StepUp"
const INTO_GRAB: StringName = &"IntoGrab"
const GRAB: StringName = &"Grab"
const WALL_RUN: StringName = &"WallRun"
const WALL_CLIMB: StringName = &"WallClimb"
const TURN_180: StringName = &"Turn180"
const TURN_180_IN_AIR: StringName = &"Turn180InAir"
const ZIPLINE: StringName = &"Zipline"
const SWING: StringName = &"Swing"
## TdMove_IntoClimb: getting onto a ladder or a pipe; Climb is on it.
const INTO_CLIMB: StringName = &"IntoClimb"
const BALANCE: StringName = &"Balance"
const LEDGE_WALK: StringName = &"LedgeWalk"
const SPRING_BOARD: StringName = &"SpringBoard"
const DODGE_JUMP: StringName = &"DodgeJump"
const VERTIGO: StringName = &"Vertigo"
const STUMBLE: StringName = &"Stumble"
const STUMBLE_HARD: StringName = &"StumbleHard"

# The original's moves this project has no counterpart for yet. The action
# table names them, so they have names; nothing registers them, so
# MoveManager.can_do() is false for every one of them and the table falls
# through to the next candidate exactly as the original does when CanDoMove()
# says no.
const BARGE: StringName = &"Barge"
const AIR_BARGE: StringName = &"AirBarge"
const MELEE: StringName = &"Melee"
const MELEE_AIR: StringName = &"MeleeAir"
const MELEE_SLIDE: StringName = &"MeleeSlide"
const MELEE_CROUCH: StringName = &"MeleeCrouch"
const MELEE_WALLRUN: StringName = &"MeleeWallrun"
const SNATCH: StringName = &"Snatch"
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

## TdMove.EMovementGroup. [ME:CONFIRMED decompile]
const MG_FREE := 0
const MG_ONE_HAND_BUSY := 1
const MG_TWO_HANDS_BUSY := 2
const MG_NON_INTERACTIVE := 3

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
## TdMove.bUseCustomCollision: [ME:CONFIRMED decompile N5 §0.2] StartMove
## shrinks the collision to the crouched height (unless the move before also
## used it), StopMove gives the standing height back (unless the move after
## uses it too). The feet stay where they are both ways.
var use_custom_collision: bool = false

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

## TdMove precise location: bUsePreciseLocation, bReachedPreciseLocation, the
## EPreciseLocationMode, the target and the speed.
var use_precise_location: bool = false
var reached_precise_location_flag: bool = false
var precise_location: Vector3 = Vector3.ZERO
var precise_location_speed: float = 4.0
var precise_location_mode: int = 0

## TdMove precise rotation: the pawn's yaw stepped toward a target, linearly,
## over PreciseRotationInterpolationTime. Rotator units.
var use_precise_rotation: bool = false
var reached_precise_rotation_flag: bool = false
var precise_rotation_yaw: int = 0
var precise_rotation_time: float = 0.0
## TdMove.bDelayRotationAndLocationCallback: one half has arrived while the
## other is still under way, and ReachedPreciseLocationAndRotation waits for
## both. Transient; StopMove does not clear it, and neither does this port.
var delay_rotation_and_location_callback: bool = false

## TdMove.bDisableCollision: no world collision while this move runs
## (Actor.bCollideWorld off from StartMove to StopMove).
var disable_collision: bool = false
## TdMove.CurrentCustomAnimName: the animation this move last played. Its end
## and its root motion ceasing reach the move only while it is this one.
var current_custom_anim_name: StringName = &""

## TdMove.MovementGroup. The player's side reads it once: LookBehind ignores
## Q in a move at MG_NON_INTERACTIVE. Only those moves declare it, plus
## MeleeVault, which drops back from its base's; the lower groups gate the
## weapon, which this project has none of.
var movement_group: int = MG_FREE

## TdMove.bDisableFaceRotation: the pawn does not follow the controller while
## this move runs. Instance state, as in the original: a move may set it at
## runtime and nothing resets it on StopMove.
var disable_face_rotation: bool = false
## TdMove.bDisableControllerFacingPawnYawRotation: a precise rotation turns
## the pawn only, not the controller (the view) with it.
var disable_controller_facing_pawn_yaw_rotation: bool = false

## TdMove's look-at state, applied by update_view_rotation(). Rotator units.
## bLookAtTargetLocation and bLookAtTargetAngle: the location wins when both
## are set.
var look_at_target_location_active: bool = false
var look_at_target_location: Vector3 = Vector3.ZERO
var look_at_target_angle_active: bool = false
var look_at_target_pitch: int = 0
var look_at_target_yaw: int = 0
var look_at_target_interpolation_time: float = 0.0
var look_at_target_duration: float = -1.0
## TdMove.bResetCameraLook: the view eased back to the pawn's yaw, level.
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
	if disable_collision:
		player.collide_world = false
	if use_custom_collision:
		var old: Move = player.move_manager.move_for(player.old_movement_state)
		if old == null or not old.use_custom_collision:
			player.shrink_collision()
	if pawn_physics != PHYS_KEEP and player.physics != pawn_physics:
		player.set_physics(pawn_physics)
	if controller_state != CS_NONE:
		player.set_controller_state(controller_state)

## The common half of TdMove.StopMove and TdPhysicsMove.StopMove. Run by the
## manager after exit(), for every move.
func end_move() -> void:
	timer = 0.0
	_move_timers.clear()
	use_precise_location = false
	use_precise_rotation = false
	if look_at_target_angle_active or look_at_target_location_active:
		abort_look_at_target()
	reset_camera_look_active = false
	if player == null:
		return
	player.stop_ignore_move_input()
	player.stop_ignore_look_input()
	if disable_collision:
		player.collide_world = true
	current_custom_anim_name = &""
	if use_custom_collision:
		var pending: Move = player.move_manager.move_for(player.pending_movement_state)
		if pending == null or not pending.use_custom_collision:
			player.enlarge_collision()
	# TdMove.StopMove: root motion and root rotation off, whatever the move
	# turned on.
	player.use_root_motion(false)
	player.use_root_rotation(false)
	last_stop_move_time = player.world_time
	if controller_state != CS_NONE:
		player.set_controller_state(CS_PLAYER_WALKING)

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

## TdMove.ReachedPreciseRotation. Empty in the original's base.
func reached_precise_rotation() -> void:
	pass

## TdMove.ReachedWall, fired by the wall physics on first contact. Empty in
## the original's base.
func reached_wall() -> void:
	pass

## TdMove.FailedToReachPreciseLocation: a PLM_Fall flight that fell past its
## target. Empty in the original's base.
func failed_to_reach_precise_location() -> void:
	pass

## TdMove.PlayMoveAnim, into the pawn's full-body slot (Player.anim_slot): the
## original's first-person timing and, with `root_motion` / `root_rotation`,
## its root motion -- which moves the body only while the pawn uses root
## motion (UseRootMotion) or root rotation. A name the original's player sets
## do not have plays nothing.
func play_slot_anim(anim: StringName, rate: float, blend_in: float, blend_out: float,
		root_motion: bool = false, root_rotation: bool = false) -> void:
	current_custom_anim_name = anim
	player.anim_slot.play(anim, rate, blend_in, blend_out, root_motion, root_rotation, player.pawn_yaw)

## Whether `anim` is this move's CurrentCustomAnimName (names compare without
## case, as the original's do).
func is_current_custom_anim(anim: StringName) -> bool:
	return String(anim).to_lower() == String(current_custom_anim_name).to_lower() and anim != &""

## TdMove.OnCustomAnimEnd / OnCeaseRelevantRootMotion. Empty in the base.
func on_custom_anim_end(_anim: StringName) -> void:
	pass

func on_cease_relevant_root_motion() -> void:
	pass

## Moves[MovementState].FrictionModifier as the wall physics reads it: the
## field, which a wall move rewrites every tick. The config's value elsewhere.
func live_friction_modifier() -> float:
	return cfg.friction_modifier if cfg != null else 1.0

## TdMove.TouchedFallHeightVolume, raised by Player.touch_fall_height_volume().
## Empty in the original's base; RumpSlide records it.
func touched_fall_height_volume() -> void:
	pass

## Native slot 0x124. Empty for TdMove; PhysicsMove overrides it.
func check_auto_moves() -> void:
	pass

## Native slot 0x118, TdMove's version: the precise location, the precise
## rotation, then the events they raise. [ME:CONFIRMED decompile N4 §2.7,
## 0x011fce10]
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
## the height left and the SCRIPT gravity; Fall leaves the vertical to the
## falling physics (_precise_fall_step()).
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
		PLM_FALL:
			_precise_fall_step(delta, to, dist2)
			return
	player.acceleration = Vector3.ZERO

## PLM_Fall. [ME:CONFIRMED decompile 0x011fce10] The horizontal as Jump's,
## the horizontal acceleration zeroed and the vertical left to the falling
## physics. Once falling with the target below and within a frame's horizontal
## reach, the vertical speed is set to land on it (gravity's frame added back)
## if the body's box can get there; falling with the target above, or blocked
## on the way, fails: bUsePreciseLocation off and FailedToReachPreciseLocation.
func _precise_fall_step(delta: float, to: Vector3, dist2: float) -> void:
	var dt: float = maxf(delta, 1e-6)
	var h: float = minf(dist2 / dt, precise_location_speed)
	var dir: Vector3 = PawnPhysics.safe_normal_2d(to)
	player.velocity.x = dir.x * h
	player.velocity.z = dir.z * h
	player.acceleration.x = 0.0
	player.acceleration.z = 0.0
	var vz: float = player.velocity.y
	if not vz < 0.0:
		return
	var here: Vector3 = player.global_position
	if precise_location.y <= here.y:
		if delta * precise_location_speed <= dist2:
			return
		var landing_vz: float = maxf(to.y / dt, vz)
		var next := Vector3(here.x + player.velocity.x * delta, here.y + landing_vz * delta,
			here.z + player.velocity.z * delta)
		if not player.traces.movement_trace_for_blocking(next, here, player.collision_extent()):
			player.velocity.y = landing_vz - player.gravity_z() * delta
			return
	use_precise_location = false
	reached_precise_location_flag = false
	delay_rotation_and_location_callback = false
	failed_to_reach_precise_location()

## One frame of the precise rotation. Once the time left is no more than this
## frame, the yaw is the target and the rotation is reached; until then the
## yaw steps by the remaining difference times dt / time left, truncated, and
## the time left shrinks by dt. The controller (the view) takes the same step
## unless bDisableControllerFacingPawnYawRotation.
func _precise_rotation_step(delta: float) -> void:
	var pawn_units: int = UE.yaw_units(player.pawn_yaw)
	if precise_rotation_time <= delta:
		player.pawn_yaw = UE.godot_yaw(precise_rotation_yaw)
		if not disable_controller_facing_pawn_yaw_rotation:
			player.set_controller_yaw(UE.godot_yaw(precise_rotation_yaw))
		reached_precise_rotation_flag = true
		return
	var step: int = int(UE.normalize_axis(precise_rotation_yaw - pawn_units) * (delta / precise_rotation_time))
	player.pawn_yaw = UE.godot_yaw(UE.normalize_axis(pawn_units + step))
	if not disable_controller_facing_pawn_yaw_rotation:
		player.set_controller_yaw(UE.godot_yaw(UE.yaw_units(player.rotation.y) + step))
	precise_rotation_time -= delta

## The reached events, in the native's order: each half that has arrived is
## switched off and raises its own event, then ReachedPreciseLocationAndRotation
## -- at once when the other half is not in use or has arrived too, else once
## that half arrives (bDelayRotationAndLocationCallback). When both arrive on
## one frame the pair event fires TWICE, once from each half. The original's,
## kept.
func _precise_events() -> void:
	var both: bool = false
	if reached_precise_location_flag:
		use_precise_location = false
		reached_precise_location_flag = false
		reached_precise_location()
		if not use_precise_rotation or reached_precise_rotation_flag:
			both = true
			if not delay_rotation_and_location_callback:
				reached_precise_location_and_rotation()
		else:
			delay_rotation_and_location_callback = true
	if reached_precise_rotation_flag:
		use_precise_rotation = false
		reached_precise_rotation_flag = false
		reached_precise_rotation()
		if not use_precise_location or reached_precise_location_flag:
			both = true
			if not delay_rotation_and_location_callback:
				reached_precise_location_and_rotation()
		else:
			delay_rotation_and_location_callback = true
	if delay_rotation_and_location_callback and both:
		delay_rotation_and_location_callback = false
		use_precise_location = false
		reached_precise_location_flag = false
		use_precise_rotation = false
		reached_precise_rotation_flag = false
		reached_precise_location_and_rotation()

## TdMove.SetPreciseLocation. `speed` < 0 takes GroundSpeed.
func set_precise_location(location: Vector3, speed: float = -1.0, mode: int = PLM_FLY) -> void:
	precise_location_speed = config.pawn.ground_speed if speed < 0.0 else speed
	precise_location = location
	precise_location_mode = mode
	use_precise_location = true
	reached_precise_location_flag = false

## TdMove.SetPreciseRotation, yaw only (the pawn never pitches). Rotator units.
func set_precise_rotation(yaw_units: int, seconds: float) -> void:
	precise_rotation_yaw = yaw_units
	precise_rotation_time = seconds
	use_precise_rotation = true
	reached_precise_rotation_flag = false

## TdMove.ReachedPreciseLocationAndRotation. Empty in the original's base.
func reached_precise_location_and_rotation() -> void:
	pass

# --- the view (TdMove.UpdateViewRotation) ---------------------------------------
#
# CameraRig asks the current move's update_view_rotation() every frame. A move
# that answers uses_view_rotation() has the view turned the original's way
# through it -- input, look-at, ConstrainAxis, reset. Any other keeps the
# rig's own look clamp for the input, and the rig takes only the look-at and
# the reset from it.

## Whether the camera turns the view through update_view_rotation() -- the
## original's look-at targets and ConstrainAxis -- while this move runs. The
## moves not yet ported keep the camera rig's own look clamp.
func uses_view_rotation() -> bool:
	return false

## TdMove.SetLookAtTargetLocation. `duration` -1 holds it until aborted.
func set_look_at_target_location(target: Vector3, interpolation_time: float,
		duration: float = -1.0) -> void:
	look_at_target_location_active = true
	look_at_target_interpolation_time = interpolation_time
	look_at_target_duration = duration if duration == -1.0 else move_active_time + duration
	look_at_target_location = target

## TdMove.SetLookAtTargetAngle. `duration` -1 holds it until aborted.
func set_look_at_target_angle(pitch_units: int, yaw_units: int, interpolation_time: float,
		duration: float = -1.0) -> void:
	look_at_target_angle_active = true
	look_at_target_interpolation_time = interpolation_time
	look_at_target_duration = duration if duration == -1.0 else move_active_time + duration
	look_at_target_pitch = pitch_units
	look_at_target_yaw = yaw_units

## TdMove.AbortLookAtTarget.
func abort_look_at_target() -> void:
	look_at_target_location_active = false
	look_at_target_angle_active = false
	look_at_target_duration = -1.0

## TdMove.ResetCameraLook.
func reset_camera_look(interpolation_time: float) -> void:
	reset_camera_look_active = true
	cancel_reset_camera_look_time = player.world_time + interpolation_time

## TdMove.GetMin/MaxLookConstrainYaw / Pitch, rotator units: the config's
## Min/MaxLookConstraint unless a move overrides them (WallRun's absolute
## window). The config holds them in radians in the original's sense, yaw
## positive turning right.
func get_min_look_constrain_yaw() -> int:
	return int(round(cfg.min_look_constraint.y * UE.UNITS_PER_RADIAN))

func get_max_look_constrain_yaw() -> int:
	return int(round(cfg.max_look_constraint.y * UE.UNITS_PER_RADIAN))

func get_min_look_constrain_pitch() -> int:
	return int(round(cfg.min_look_constraint.x * UE.UNITS_PER_RADIAN))

func get_max_look_constrain_pitch() -> int:
	return int(round(cfg.max_look_constraint.x * UE.UNITS_PER_RADIAN))

## bConstrainLook as this move has it now: the config's, unless a move turns
## it off and on at runtime (Grab).
func constrains_look() -> bool:
	return cfg != null and cfg.constrain_look

## TdMove.PostConstrainCamera: `constrain_amount` is what the constraint took
## off this frame's input, (pitch, yaw); returns the input to use. Empty in the
## base.
func post_constrain_camera(_constrain_amount: Vector2i, delta_rot: Vector2i) -> Vector2i:
	return delta_rot

## The look-at's pull on `head`: Normalize(wanted - head) times
## min(1, dt / interpolation time), each axis truncated.
func _look_at_pull(head: Vector2i, wanted: Vector2i, dt: float) -> Vector2i:
	var d := Vector2i(UE.normalize_axis(wanted.x - head.x), UE.normalize_axis(wanted.y - head.y))
	var k: float = minf(1.0, dt / look_at_target_interpolation_time)
	return Vector2i(int(d.x * k), int(d.y * k))

## TdMove.UpdateViewRotation. [ME:CONFIRMED decompile TdMove.uc] All in rotator
## units: `view` is the controller's (pitch, yaw), `delta_rot` this frame's
## input (pitch, yaw). Returns [view, delta_rot]; the caller then adds the
## delta to the view (ProcessViewRotation). `now` is WorldInfo.TimeSeconds.
##
## The look-at target -- a location seen from the eyes (Location + 76 uu,
## GetActorEyesViewPoint), else an angle -- pulls the view by
## dt / interpolation time of what is left; then the constraint, measured
## against the PAWN's rotation (absolute windows are taken relative to it
## first), through CameraRig.constrain_axis with an interpolation of dt / 0.2;
## then the reset toward the pawn's yaw.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	var out: Vector2i = view
	if look_at_target_location_active or look_at_target_angle_active:
		if look_at_target_duration == -1.0 or look_at_target_duration >= move_active_time:
			var wanted := Vector2i(look_at_target_pitch, look_at_target_yaw)
			if look_at_target_location_active:
				var eye: Vector3 = player.global_position + Vector3.UP * player.BASE_EYE_HEIGHT
				var dir: Vector3 = look_at_target_location - eye
				wanted = Vector2i(UE.dir_pitch(dir), UE.dir_yaw(dir))
			var head := Vector2i(UE.normalize_axis(out.x), UE.normalize_axis(out.y))
			out += _look_at_pull(head, wanted, dt)
		else:
			abort_look_at_target()
	var pawn_yaw_units: int = UE.yaw_units(player.pawn_yaw)
	if cfg != null and constrains_look():
		var before: Vector2i = delta_rot
		var controller_delta := Vector2i(UE.normalize_axis(UE.normalize_axis(out.x)),
			UE.normalize_axis(UE.normalize_axis(out.y) - pawn_yaw_units))
		var min_yaw: int
		var max_yaw: int
		if cfg.absolute_yaw_constraint:
			min_yaw = UE.normalize_axis(get_min_look_constrain_yaw() - pawn_yaw_units)
			max_yaw = UE.normalize_axis(get_max_look_constrain_yaw() - pawn_yaw_units)
		else:
			# Against the pawn's own MinLookConstraint, (-32768, 32768) here.
			min_yaw = maxi(get_min_look_constrain_yaw(), -32768)
			max_yaw = mini(get_max_look_constrain_yaw(), 32768)
		var min_pitch: int = maxi(get_min_look_constrain_pitch(), -32768)
		var max_pitch: int = mini(get_max_look_constrain_pitch(), 32768)
		var speed: float = dt / 0.2
		var yaw: int = CameraRig.constrain_axis(controller_delta.y, min_yaw, max_yaw, speed, delta_rot.y)
		var pitch: int = CameraRig.constrain_axis(controller_delta.x, min_pitch, max_pitch, speed, delta_rot.x)
		delta_rot = post_constrain_camera(before - Vector2i(pitch, yaw), Vector2i(pitch, yaw))
		delta_rot = Vector2i(UE.normalize_axis(delta_rot.x), UE.normalize_axis(delta_rot.y))
	if reset_camera_look_active:
		if cancel_reset_camera_look_time > now:
			var head := Vector2i(UE.normalize_axis(out.x), UE.normalize_axis(out.y))
			var d := Vector2i(UE.normalize_axis(0 - head.x), UE.normalize_axis(pawn_yaw_units - head.y))
			var div: float = maxf(1.0, (cancel_reset_camera_look_time - now) / dt)
			out += Vector2i(int(d.x / div), int(d.y / div))
		else:
			out.x = 0
			reset_camera_look_active = false
	return [out, delta_rot]

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
## seconds. The config's redo_move_time by default; a move not yet ported may
## override it when it can tell that THIS exit is not the kind the cooldown
## guards. Asked by MoveManager._arm_cooldown() after exit().
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

# --- automatic transitions (TdPhysicsMove::CheckAutoMoves) ------------------------

## The three bCheckFor* switches as this move instance has them now: the
## config's value (the original's ini) unless the move has cleared them at
## runtime (auto_checks_cleared), as WallClimbDodgeJump and
## WallClimb180TurnJump do.
var auto_checks_cleared: bool = false

func checks_grab() -> bool:
	var c: MoveConfig = current_config()
	return c != null and c.check_for_grab and not auto_checks_cleared

func checks_vault_over() -> bool:
	var c: MoveConfig = current_config()
	return c != null and c.check_for_vault_over and not auto_checks_cleared

func checks_wall_climb() -> bool:
	var c: MoveConfig = current_config()
	return c != null and c.check_for_wall_climb and not auto_checks_cleared

## bCheckForEdgeInVelDir and bDelayTimeCheckAutoMoves. TdPhysicsMove's; a
## plain move answers the CDO defaults.
func edge_in_vel_dir() -> bool:
	return false

func auto_move_delay() -> float:
	return -1.0

## TdPhysicsMove.FoundReachableHandPlant: an event on the current move when
## the hand-plant search found a top. Empty in the base.
func found_reachable_hand_plant() -> void:
	pass

## The original's automatic transitions, in its order. [ME:CONFIRMED decompile
## N4 §2.2, listing-checked] Returns the move to set, or KEEP; the side
## effects on the pawn (MoveLedgeResult, the ledge, bFoundLedge) happen here
## as they do in the original.
##
##   0. nothing while all three velocity components are under 1e-4 uu/s
##   1. bCheckForWallClimb: WallRun.CanDoMove(), which also picks the side.
##      NOT gated by bDelayTimeCheckAutoMoves -- only the search below is.
##   2. the hand-plant search, once MoveActiveTime > bDelayTimeCheckAutoMoves
##      and any switch is on: MoveLedgeResult 0 / 1 (wall) / 2 (a top)
##   3. bCheckForWallClimb and a result: WallClimb's native gate
##   4. a top: FoundReachableHandPlant, bFoundLedge
##   5. bCheckForVaultOver: AutoStepUp's CanDoMove (always false), then
##      VaultOver's, which plans the vault
##   6. bCheckForGrab: IntoGrab's native gate
## The two native gates skip the script's CanDoMove, RedoMoveTime included.
func auto_move_target() -> StringName:
	var v: Vector3 = player.velocity
	var still: float = 1e-4 * UU
	if absf(v.x) < still and absf(v.y) < still and absf(v.z) < still:
		return KEEP
	var manager = player.move_manager
	var wall_climb_on: bool = checks_wall_climb()
	if wall_climb_on and manager.can_do(WALL_RUN):
		return WALL_RUN
	player.move_ledge_result = MoveTraces.LEDGE_NONE
	if move_active_time > auto_move_delay() and (checks_grab() or checks_vault_over() or wall_climb_on):
		var hit: Dictionary = player.traces.find_auto_move_ledge(player.global_position, player.facing(),
			MoveTraces.HAND_PLANT_CHECK_DISTANCE, true, edge_in_vel_dir())
		player.move_ledge_result = hit["result"]
		if hit["result"] != MoveTraces.LEDGE_NONE:
			player.move_ledge_location = hit["ledge_location"]
			player.move_ledge_normal = hit["ledge_normal"]
			player.move_normal = hit["move_normal"]
	if player.move_ledge_result <= MoveTraces.LEDGE_NONE:
		return KEEP
	if wall_climb_on:
		var climb: Move = manager.move_for(WALL_CLIMB)
		if climb != null and climb.can_do_move_native():
			return WALL_CLIMB
	if player.move_ledge_result != MoveTraces.LEDGE_TOP:
		return KEEP
	found_reachable_hand_plant()
	player.found_ledge = true
	if checks_vault_over():
		if manager.can_do(AUTO_STEP_UP):
			return AUTO_STEP_UP
		if manager.can_do(VAULT_OVER):
			return VAULT_OVER
	if checks_grab():
		var reach: Move = manager.move_for(INTO_GRAB)
		if reach != null and reach.can_do_move_native():
			return INTO_GRAB
	return KEEP

## A native CanDoMove the automatic transitions ask directly, bypassing the
## script's (RedoMoveTime included). Only WallClimb and IntoGrab have one;
## everything else answers false, as the base slot does.
func can_do_move_native() -> bool:
	return false

## What the moves not yet ported ask from their own physics_update(): the
## original's automatic transitions.
func legacy_probe_transition() -> StringName:
	return auto_move_target()
