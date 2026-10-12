class_name WallClimb180TurnJumpMove
extends PhysicsMove

# The original's TdMove_WallClimb180TurnJump, ported (MOVE_WallClimb180TurnJump,
# 50). [ME:CONFIRMED decompile 15.5] Q on a wall climb: the body turns away
# from the wall on the animation's own root rotation, the view is reset onto
# it, and for JumpTimeWindow (0.6 s) a jump press pushes straight off the wall
# at 400 uu/s with a 250 uu jump. When the window closes the root rotation
# stops, the view is drawn to face off the wall and the pawn is turned there
# in 0.1 s; reaching that rotation hands to Falling.
#
# The grab, vault and wall-climb switches are cleared for the whole move: only
# a jump taken in the window gives them back, on the move's last frame.

## The 1P root rotation of `wallrunvertical180turn` [ME:CONFIRMED anims
## root_motion]: degrees turned (rightward, the original's sense) at 60 Hz
## over its 0.633 s.
const ROOT_YAW_DEGREES: PackedFloat32Array = [0.0, 0.639, 1.279, 2.956, 4.762, 7.35, 10.163,
	13.532, 17.183, 21.208, 25.538, 30.092, 34.934, 39.887, 45.077, 50.303, 55.679, 61.053,
	66.447, 71.84, 77.093, 82.347, 87.323, 92.267, 97.28, 102.319, 107.687, 113.23, 118.97,
	124.882, 130.887, 137.03, 143.195, 149.432, 155.65, 161.837, 167.951, 173.529, 179.105]
const ROOT_SAMPLE_RATE := 60.0

var jumping_from_wall: bool = false
## The wall's flat normal at the start: where the jump goes.
var wanted_jump_dir: Vector3 = Vector3.ZERO
var _root_start_yaw: int = 0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true
	# [ME:CONFIRMED decompile] CDO: ExitToFallingZSpeed -800 uu/s,
	# DisableMovementTime 0.4 s.
	exit_to_falling_z_speed = -8.0
	disable_movement_time = 0.4

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func can_do_move() -> bool:
	return td_can_do_move() and player.move_manager.current_name == WALL_CLIMB

## The root rotation's yaw, in rotator units, `seconds` into the animation.
static func root_yaw_units(seconds: float) -> int:
	var at: float = clampf(seconds * ROOT_SAMPLE_RATE, 0.0, ROOT_YAW_DEGREES.size() - 1.0)
	var i: int = int(at)
	var j: int = mini(i + 1, ROOT_YAW_DEGREES.size() - 1)
	var degrees: float = lerpf(ROOT_YAW_DEGREES[i], ROOT_YAW_DEGREES[j], at - i)
	return int(round(degrees * UE.UNITS_PER_TURN / 360.0))

## TdMove_WallClimb180TurnJump.StartMove.
func enter(_previous: StringName) -> void:
	var c: WallClimb180TurnJumpConfig = cfg as WallClimb180TurnJumpConfig
	wanted_jump_dir = Vector3(player.floor_normal.x, 0.0, player.floor_normal.z).normalized()
	jumping_from_wall = false
	player.using_root_rotation = true
	_root_start_yaw = UE.yaw_units(player.pawn_yaw)
	reset_camera_look(0.2)
	auto_checks_cleared = true
	set_timer(c.jump_time_window)

## The animation turns the pawn while the root rotation is on.
func pre_physics(delta: float) -> void:
	if player.using_root_rotation:
		player.pawn_yaw = UE.godot_yaw(_root_start_yaw + root_yaw_units(move_active_time + delta))
	super.pre_physics(delta)

func handle_move_action(action: int) -> void:
	var c: WallClimb180TurnJumpConfig = cfg as WallClimb180TurnJumpConfig
	if action == MA_JUMP and not jumping_from_wall and move_active_time < c.jump_time_window:
		jump_from_wall()

## TdMove_WallClimb180TurnJump.JumpFromWall: the height as a speed under the
## script's gravity, 2 g sqrt(h / g), and the push straight off the wall.
func jump_from_wall() -> void:
	var c: WallClimb180TurnJumpConfig = cfg as WallClimb180TurnJumpConfig
	jumping_from_wall = true
	reset_camera_look(0.2)
	player.last_jump_location = player.global_position
	var height: float = c.jump_off_z_height
	var start: Vector3 = player.global_position + wanted_jump_dir * 2.0 * UU
	var up: Dictionary = player.traces.movement_trace(start + Vector3.UP * height, start,
		player.collision_extent())
	if up["hit"]:
		height = (up["location"] as Vector3).y - player.global_position.y
	var gravity: float = absf(player.gravity_z())
	player.velocity = wanted_jump_dir * c.jump_push_away_speed
	player.velocity.y = gravity * 2.0 * sqrt(height / gravity)

## The window has closed: the root rotation stops, the view and then the pawn
## face off the wall.
func on_timer() -> void:
	player.using_root_rotation = false
	var yaw: int = UE.dir_yaw(wanted_jump_dir)
	set_look_at_target_angle(player.controller_pitch_units(), yaw, 0.2)
	set_precise_rotation(yaw, 0.1)

func reached_precise_rotation() -> void:
	if jumping_from_wall:
		auto_checks_cleared = false
	player.stop_ignore_move_input()
	player.move_manager.set_move(FALLING)

## Whether the push off the wall was taken, for the animation.
func jumped() -> bool:
	return jumping_from_wall
