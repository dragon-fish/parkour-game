class_name ClimbMove
extends PhysicsMove

# The original's TdMove_Climb (MOVE_Climb 21): on a ladder or a pipe.
# [ME:CONFIRMED decompile script TdMove_Climb.uc; PrePhysics 0x0120abe0 read,
# N5 §15]
#
# Stepwise: PlayerGrabbing's climb actions move the body one step (two on a
# pipe with room) as a PLM_Fly precise location at 96 uu/s a step on a
# ladder, 64 on a pipe, with the step's animation; nothing more is taken
# until the step is reached. Only while the view is within 90 degrees of the
# ladder. At the top a climb up plays the exit, whose root motion carries the
# body off with collision off; its end hands to Walking (at 300 uu/s if
# pushing forward). Pulled fully back above the fourth step, the body slides
# down at half the script gravity until the stick lets go or two steps from
# the bottom, then settles on the step below. Crouch lets go (Walking if a
# floor is within 32 uu of the feet, otherwise Falling). Jump asks
# GrabTransfer, then GrabJump.
#
# Kept: HasFloorBelow traces from a point to itself and never hits, so a
# climb down at the bottom step and the end of a slide never let go onto the
# floor through it.

enum State { CLIMBING, EXIT_AT_TOP, EXIT_AT_BOTTOM }

var climb_state: int = State.CLIMBING
var wanted_action: int = MA_NONE
var is_playing_animation: bool = false
var ladder: LadderVolume = null
## TdPawn.bClimbLeftHand / bClimbDownFast.
var climb_left_hand: bool = false
var climb_down_fast: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_GRABBING
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## TdMove_Climb.HandleDeath: the exit at the top survives with one point;
## anything else lets go into Falling and dies.
func handle_death(damage: float) -> float:
	if climb_state == State.EXIT_AT_TOP:
		return player.health.hp - 1.0
	player.move_manager.set_move(FALLING)
	return damage

func uses_view_rotation() -> bool:
	return true

func _climb_cfg() -> ClimbConfig:
	return cfg as ClimbConfig

func can_do_move() -> bool:
	return td_can_do_move()

## TdMove_Climb.StartMove.
func enter(_previous: StringName) -> void:
	(player.move_manager.move_for(GRAB_TRANSFER) as GrabTransferMove).ladder = ladder
	reset_camera_look(0.3)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.set_collision_radius(player.default_collision_radius() - 5.0 * UU)

## TdMove_Climb.StopMove.
func exit() -> void:
	_reset()
	ladder = null
	player.use_root_motion(false)
	player.use_root_rotation(false)
	player.collide_world = true
	player.face_rotation_time_left = 0.2
	var into: Move = player.move_manager.move_for(INTO_CLIMB)
	if into != null:
		into.last_stop_move_time = player.world_time
	player.set_collision_radius(player.default_collision_radius())

func _reset() -> void:
	climb_left_hand = false
	climb_down_fast = false
	is_playing_animation = false
	wanted_action = MA_NONE
	climb_state = State.CLIMBING

## UTdMove_Climb::GetAimMode with bAimingOnly: hands free only while the view
## is within StartTurningAngle of the ladder.
func view_within_hands_reach() -> bool:
	var yaw: int = UE.normalize_axis(UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw))
	var limit: int = _climb_cfg().start_turning_angle
	return yaw <= limit and yaw >= -limit

## TdMove_Climb.HandleMoveAction.
func handle_move_action(action: int) -> void:
	if action == MA_CROUCH and climb_state != State.EXIT_AT_TOP and climb_state != State.EXIT_AT_BOTTOM:
		let_go()
		return
	if action == MA_TURN:
		# The raw difference of the two yaws picks the side, unnormalised.
		var raw: int = UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw)
		var yaw: int = UE.yaw_units(player.pawn_yaw) + (32768 if raw > 0 else -32768)
		abort_look_at_target()
		set_look_at_target_angle(0, UE.normalize_axis(yaw), 0.2, 1.0)
	wanted_action = action
	if is_playing_animation or use_precise_location:
		abort_look_at_target()
		return
	if not climb_down_fast and player.move_action_hint == MAH_DOWN and player.move_action_max \
			and ladder.get_closest_step(player.global_position.y) > 4:
		climb_down_fast = true
		reset_camera_look(0.3)
		player.set_ignore_look_input(-1.0)
	if not climb_down_fast and action != MA_NONE and view_within_hands_reach():
		handle_climb_action()

## TdMove_Climb.HasFloorBelow: a zero-extent trace whose two ends are the same
## point, 20 uu under the step.
func has_floor_below() -> bool:
	var at: Vector3 = ladder.get_ladder_location(ladder.get_closest_step(player.global_position.y)) \
		- Vector3.UP * 20.0 * UU
	return player.traces.movement_trace_for_blocking(at, at)

## TdMove_Climb.StopClimbDownFast, raised by the native when the slide ends.
func stop_climb_down_fast() -> void:
	if use_precise_location:
		return
	if has_floor_below():
		let_go()
		return
	var below: int = ladder.get_closest_step_down(player.global_position.y)
	set_precise_location(ladder.get_ladder_location(below),
		maxf(100.0 * UU, float(int(player.velocity.y / UU)) * UU), PLM_FLY)

func on_cease_relevant_root_motion() -> void:
	if climb_state == State.EXIT_AT_TOP or climb_state == State.EXIT_AT_BOTTOM:
		if player.move_action_hint == MAH_UP:
			player.velocity = player.facing() * 300.0 * UU
			player.acceleration = PawnPhysics.safe_normal(player.velocity)
			player.set_acceleration_time(0.2)
		player.move_manager.set_move(WALKING)

## TdMove_Climb.HandleClimbAction.
func handle_climb_action() -> void:
	var current: int = ladder.get_closest_step(player.global_position.y)
	var pipe: bool = ladder.is_pipe()
	if wanted_action == MA_CLIMB_UP or wanted_action == MA_CLIMB_UP_LONG:
		if current == ladder.get_last_step():
			if ladder.line.can_exit_at_top:
				exit_at_top(4 if climb_left_hand else 5)
		elif pipe and ladder.get_last_step() - current > 1:
			climb(3 if climb_left_hand else 2, 1.0, 2)
		else:
			climb(1 if climb_left_hand else 0, 1.0, 1)
	elif wanted_action == MA_CLIMB_DOWN or wanted_action == MA_CLIMB_DOWN_LONG:
		if current > 1:
			if pipe and current > 2:
				climb(2 if climb_left_hand else 3, -1.0, -2)
			else:
				climb(0 if climb_left_hand else 1, -1.0, -1)
		elif has_floor_below():
			let_go()

## ClimbAnims, by ladder type: 0/1 hand over hand, 2/3 fast, 4/5 off the top.
func climb_anim(index: int) -> StringName:
	var pipe: bool = ladder.is_pipe()
	match index:
		0:
			return &"PipeClimbUpLeftHand" if pipe else &"LadderClimbUpLeftHand"
		1:
			return &"PipeClimbUpRightHand" if pipe else &"LadderClimbUpRightHand"
		2:
			return &"PipeClimbUpFastLeftHand" if pipe else &"LadderClimbUpFastLeftHand"
		3:
			return &"PipeClimbUpFastRightHand" if pipe else &"LadderClimbUpFastRightHand"
		4:
			return &"PipeExitTopRightHand" if pipe else &"LadderExitTopRightHand"
		_:
			return &"PipeExitTopLeftHand" if pipe else &"LadderExitTopLeftHand"

## TdMove_Climb.Climb: a step, or two.
func climb(index: int, rate: float, step_count: int) -> void:
	var speed: float = absf(float(step_count)) * (64.0 if ladder.is_pipe() else 96.0) * UU
	play_slot_anim(climb_anim(index), rate, 0.1, 0.075)
	is_playing_animation = true
	set_timer(0.1)
	var target: Vector3 = ladder.get_ladder_location(ladder.get_closest_step(player.global_position.y) + step_count)
	set_precise_location(target, speed, PLM_FLY)

## TdMove_Climb.ExitAtTop.
func exit_at_top(index: int) -> void:
	play_slot_anim(climb_anim(index), 1.0, 0.1, 0.1, true)
	is_playing_animation = true
	reset_camera_look(0.1)
	player.set_ignore_look_input(-1.0)
	set_move_timer(0.9, false, player.stop_ignore_look_input)
	player.use_root_motion(true)
	climb_state = State.EXIT_AT_TOP
	player.collide_world = false

func reached_precise_location() -> void:
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.use_root_motion(false)
	player.use_root_rotation(false)
	player.collide_world = true
	player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(-ladder.wall_normal()))
	is_playing_animation = false
	climb_down_fast = false
	player.stop_ignore_look_input()

func hit_wall(_normal: Vector3, _collider: Object) -> void:
	let_go()

func landed(_normal: Vector3) -> void:
	let_go()

## TdMove_Climb.LetGo: Walking with a floor within 32 uu under the feet,
## otherwise Falling.
func let_go() -> void:
	var extent: Vector3 = player.collision_extent()
	extent.y = 16.0 * UU
	var start: Vector3 = player.global_position - Vector3.UP * player.collision_half_height()
	var end: Vector3 = start - Vector3.UP * 32.0 * UU
	if player.traces.movement_trace(end, start, extent)["hit"]:
		player.move_manager.set_move(WALKING)
	else:
		player.move_manager.set_move(FALLING)
	play_slot_anim(&"PipeExitBottom", 1.0, 0.1, 0.4)

func on_timer() -> void:
	climb_left_hand = not climb_left_hand

## UTdMove_Climb's native PrePhysics. [ME:CONFIRMED decompile 0x0120abe0]
func pre_physics(delta: float) -> void:
	if climb_down_fast:
		player.velocity.y += player.gravity_z() * delta * 0.5
		if player.move_action_hint == MAH_DOWN and player.move_action_max \
				and ladder.get_closest_step(player.global_position.y + player.velocity.y * delta) >= 2:
			super.pre_physics(delta)
			return
		stop_climb_down_fast()
		super.pre_physics(delta)
		return
	elif not is_playing_animation:
		player.velocity.y = 0.0
	super.pre_physics(delta)

## Look constraints: pitch down to -11000 once the view is turned past
## StartTurningAngle, yaw +-StartTurningAngle while a step plays.
func get_min_look_constrain_pitch() -> int:
	var yaw: int = absi(UE.normalize_axis(UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw)))
	return -11000 if yaw > _climb_cfg().start_turning_angle else super.get_min_look_constrain_pitch()

func get_min_look_constrain_yaw() -> int:
	return -_climb_cfg().start_turning_angle if is_playing_animation else super.get_min_look_constrain_yaw()

func get_max_look_constrain_yaw() -> int:
	return _climb_cfg().start_turning_angle if is_playing_animation else super.get_max_look_constrain_yaw()

## TdMove_Climb.PostConstrainCamera: a pitch held down by the constraint
## turns the view half as much sideways, toward the side it is turned, while
## within 12000 units of the ladder.
func post_constrain_camera(constrain_amount: Vector2i, delta_rot: Vector2i) -> Vector2i:
	var yaw: int = UE.normalize_axis(UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw))
	if absi(yaw) > 12000:
		return delta_rot
	if constrain_amount.x < 0:
		var raw: int = UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw)
		if raw > 0:
			if delta_rot.y >= 0:
				delta_rot.y -= int(constrain_amount.x * 0.5)
		elif delta_rot.y <= 0:
			delta_rot.y += int(constrain_amount.x * 0.5)
	return delta_rot

## For the animation: -1 down, 0 still, +1 up.
func climb_direction() -> int:
	if climb_down_fast:
		return -1
	if not is_playing_animation:
		return 0
	return 1 if precise_location.y > player.global_position.y else -1

func is_exiting_top() -> bool:
	return climb_state == State.EXIT_AT_TOP
