class_name IntoClimbMove
extends PhysicsMove

# The original's TdMove_IntoClimb (MOVE_IntoClimb 22): getting onto a ladder
# or a pipe. [ME:CONFIRMED decompile script TdMove_IntoClimb.uc]
#
# Asked every tick the body is inside a ladder's volume (the ladder volume's
# PawnUpdate), from any move but the climb itself: from Walking only with the
# stick pushed forward (hint Up), never with it pulled back; below the top it
# wants the body facing the ladder (within 96 degrees) and in front of it,
# above the top facing straight away from it (backing down; ladders only).
# The way on is a precise flight to the closest step in 0.15 s (at least 30
# uu of it), turning to the ladder; from the top, a flight to the top floor
# behind it at 500 uu/s and then LadderEnterTop, whose root motion and
# rotation carry the body over the edge and round. Then Climb.

enum EnterState { AT_TOP, AT_BOTTOM, FALLING }

var climb_state: int = EnterState.FALLING
var ladder: LadderVolume = null
var at_bottom_step: bool = false
var playing_impact: bool = false

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_WALKING
	disable_movement_time = -1.0
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

## TdMove_IntoClimb.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	if ladder == null or not ladder.is_valid():
		return false
	var state: StringName = player.movement_state
	if state == WALKING and player.move_action_hint != MAH_UP:
		return false
	if player.move_action_hint == MAH_DOWN:
		return false
	if state == CLIMB or state == INTO_CLIMB:
		return false
	var angle: float = player.facing().dot(ladder.rotation_dir())
	var to_ladder: Vector3 = ladder.location() - player.global_position
	to_ladder.y = 0.0
	var behind: bool = to_ladder.dot(ladder.rotation_dir()) < 0.0
	if player.global_position.y > ladder.get_ladder_location(ladder.get_last_step()).y:
		if angle > -0.85 or ladder.is_pipe():
			return false
	elif angle < -0.1 or behind:
		return false
	return true

## TdMove_IntoClimb.StartMove.
func enter(_previous: StringName) -> void:
	playing_impact = false
	var climb: ClimbMove = player.move_manager.move_for(CLIMB) as ClimbMove
	climb.climb_left_hand = false
	climb.climb_down_fast = false
	var current: int = clampi(ladder.get_closest_step(player.global_position.y), 0, ladder.get_last_step())
	at_bottom_step = current == 0
	reset_camera_look(0.3)
	var angle: float = player.facing().dot(ladder.rotation_dir())
	player.collide_world = false
	player.move_normal = ladder.wall_normal()
	var top: Vector3 = ladder.get_ladder_location(ladder.get_last_step())
	if not ladder.is_pipe() and angle < -0.85 and top.y < player.global_position.y:
		climb_state = EnterState.AT_TOP
		set_precise_location(top - ladder.wall_normal() * 93.5 * UU + ladder.move_direction() * 90.0 * UU,
			500.0 * UU, PLM_FLY)
	else:
		climb_state = EnterState.FALLING
		play_start_animation()
		var target: Vector3 = ladder.get_ladder_location(current)
		var d: Vector3 = target - player.global_position
		set_precise_location(target, maxf(Vector2(d.x, d.z).length(), 30.0 * UU) / 0.15, PLM_FLY)
		set_precise_rotation(UE.dir_yaw(-ladder.wall_normal()), 0.15)
		player.face_rotation_time_left = 0.15

## TdMove_IntoClimb.PlayStartAnimation: the catch, by how it was come at.
func play_start_animation() -> void:
	var pipe: bool = ladder.is_pipe()
	var old: StringName = player.old_movement_state
	if old == WALL_RUN:
		var wall_run = player.move_manager.move_for(WALL_RUN)
		var left: bool = wall_run != null and wall_run.side == WallRunMove.SIDE_LEFT
		if left:
			play_slot_anim(&"PipeClimbHangStartLeft" if pipe else &"LadderClimbHangStartLeft", 1.0, 0.15, 0.25)
		else:
			play_slot_anim(&"PipeClimbHangStartRight" if pipe else &"LadderClimbHangStartRight", 1.0, 0.15, 0.25)
		playing_impact = true
	elif old == GRAB_TRANSFER:
		var side: float = UE.cross(ladder.rotation_dir(), Vector3.UP).dot(player.facing())
		if side > 0.0:
			play_slot_anim(&"PipeClimbHangStartRight" if pipe else &"LadderClimbHangStartRight", 1.0, 0.15, 0.25)
		else:
			play_slot_anim(&"PipeClimbHangStartLeft" if pipe else &"LadderClimbHangStartLeft", 1.0, 0.15, 0.25)
		playing_impact = true
	elif player.velocity.y < -800.0 * UU:
		play_slot_anim(&"PipeClimbHangStartHard" if pipe else &"LadderClimbHangStartHard", 1.0, 0.1, 0.25)
		player.take_damage(1.0, Health.Cause.FALL)
		playing_impact = true
	elif player.velocity.y < -200.0 * UU or old == GRAB_TRANSFER:
		play_slot_anim(&"PipeClimbHangStart" if pipe else &"LadderClimbHangStart", 1.0, 0.1, 0.25)
		playing_impact = true
	elif pipe:
		play_slot_anim(&"PipeClimbStart", 1.0, 0.15, 0.25)

## TdMove_IntoClimb.StopMove.
func exit() -> void:
	player.collide_world = true
	ladder = null

func reached_precise_location() -> void:
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	player.set_ignore_move_input(-1.0)
	if climb_state == EnterState.AT_TOP:
		play_slot_anim(&"LadderEnterTop", 1.0, 0.25, 0.1, true, true)
		player.use_root_rotation(true)
		player.use_root_motion(true)
		player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(ladder.wall_normal()))
		(player.move_manager.move_for(CLIMB) as ClimbMove).climb_left_hand = true
	else:
		start_climb_move()

## TdMove_IntoClimb.StartClimbMove: square to the ladder on the closest step,
## then Climb. After an impact the stick stays ignored for the animation's
## length less 0.5 s.
func start_climb_move() -> void:
	player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(-ladder.wall_normal()))
	player.global_position = ladder.get_ladder_location(ladder.get_closest_step(player.global_position.y))
	var climb: ClimbMove = player.move_manager.move_for(CLIMB) as ClimbMove
	if climb.can_do_move() and ladder != null:
		var impact: bool = playing_impact
		var length: float = player.anim_slot.current_length()
		player.move_manager.set_move(CLIMB)
		if impact:
			player.set_ignore_move_input(maxf(0.1, length - 0.5))
	else:
		player.move_manager.set_move(FALLING)

func on_custom_anim_end(_anim: StringName) -> void:
	if climb_state == EnterState.AT_TOP:
		start_climb_move()

func failed_to_reach_precise_location() -> void:
	if climb_state == EnterState.AT_TOP or climb_state == EnterState.AT_BOTTOM:
		player.move_manager.set_move(FALLING)
		return
	if at_bottom_step:
		player.move_manager.set_move(FALLING)
		return
	var current: int = ladder.get_closest_step(player.global_position.y)
	at_bottom_step = current == 0
	set_precise_location(ladder.get_ladder_location(current),
		maxf(player.horizontal_speed(), 200.0 * UU), PLM_FALL)

## The ladder volume's PawnUpdate: every tick inside it, unless already on it.
func volume_pawn_update(line: InterestLine) -> bool:
	var state: StringName = player.movement_state
	if state == CLIMB or state == INTO_CLIMB:
		return false
	var climb: ClimbMove = player.move_manager.move_for(CLIMB) as ClimbMove
	ladder = LadderVolume.new(line)
	climb.ladder = ladder
	if can_do_move():
		player.move_manager.set_move(INTO_CLIMB)
		return true
	ladder = null
	climb.ladder = null
	return false
