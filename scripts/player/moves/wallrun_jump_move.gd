class_name WallrunJumpMove
extends PhysicsMove

# The original's TdMove_WallrunJump, ported: the jump off a wall run, its own
# state (MOVE_WallRunJump, 12). [ME:CONFIRMED decompile 15.5]
#
#   p  = the wall's flat normal . the camera's flat direction
#        (the normal itself after a Q turn, so 1)
#   h  = 100 + 60 p uu, or the headroom
#   Vz = 2 g sqrt(h / g) / (1 + ConsequtiveWallruns), g the SCRIPT gravity
#   Vxy = normal (120 + 400 p) + along-wall velocity (0.1 + 0.9 (1 - p))
#
# p is NOT clamped: the original computes FMax(0, p) and throws the result
# away. DO NOT clamp it: with the camera turned toward the wall (p < 0) the
# push points INTO the wall and more than all of the along-wall speed is kept,
# while a camera turned away from it (p near 1) trades the run's speed for the
# push. No rule says so; it is this arithmetic.
#
# The jump also arms the ledge ban: for 2 s (or until Walking), the wall left
# behind refuses hands and a forward wall run (MoveTraces, WallRunMove).

## The yaw window StartMove builds, rotator units. bConstrainLook is not set,
## so nothing applies it.
var min_contraint_world: int = 0
var max_contraint_world: int = 0
## WallRunningJumpOffZSpeed: the vertical speed, floored at 10 uu/s (written,
## never read).
var wall_running_jump_off_z_speed: float = 0.0
## p as this jump had it, and which wall it left. For the animation.
var push_speed: float = 0.0
var from_left_wall: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func get_min_look_constrain_yaw() -> int:
	return min_contraint_world

func get_max_look_constrain_yaw() -> int:
	return max_contraint_world

func can_do_move() -> bool:
	return td_can_do_move()

## TdMove_WallrunJump.StartMove.
func enter(_previous: StringName) -> void:
	var c: WallrunJumpConfig = cfg as WallrunJumpConfig
	var wall_run: WallRunMove = player.move_manager.move_for(WALL_RUN)
	var saved_floor: Vector3 = player.floor_normal
	var wall_yaw: int = UE.dir_yaw(saved_floor)
	player.illegal_ledge_timer = 2.0
	player.illegal_ledge_normal = saved_floor
	from_left_wall = player.old_movement_state == WALL_RUN and wall_run.side == WallRunMove.SIDE_LEFT
	if from_left_wall:
		min_contraint_world = UE.normalize_axis(wall_yaw - 16000)
		max_contraint_world = UE.normalize_axis(wall_yaw + 10000)
	else:
		min_contraint_world = UE.normalize_axis(wall_yaw - 10000)
		max_contraint_world = UE.normalize_axis(wall_yaw + 16000)
	player.last_jump_location = player.global_position
	var v: Vector3 = player.velocity
	var along: Vector3 = v - saved_floor * v.dot(saved_floor)
	along.y = 0.0
	var wall_dir := Vector3(saved_floor.x, 0.0, saved_floor.z).normalized()
	var camera: Vector3
	if wall_run.turned_90_from_wall:
		camera = saved_floor
		player.face_rotation_time_left = 0.1
		set_look_at_target_angle(UE.dir_pitch(saved_floor), wall_yaw, 0.1)
		set_precise_rotation(wall_yaw, 0.1)
		# Instance state: never set back, as in the original.
		disable_controller_facing_pawn_yaw_rotation = true
	else:
		camera = UE.rot_dir(player.controller_pitch_units(), UE.yaw_units(player.rotation.y))
	camera.y = 0.0
	camera = camera.normalized()
	push_speed = wall_dir.dot(camera)
	# FMax(0, PushSpeed): computed and discarded in the original.
	var height: float = c.wall_running_jump_off_z_height_forward \
		+ push_speed * c.wall_running_jump_off_z_height_max_add_turned
	var l: Vector3 = player.global_position
	var up: Dictionary = player.traces.movement_trace(l + Vector3.UP * height, l, player.collision_extent())
	if up["hit"]:
		height = (up["location"] as Vector3).y - l.y
	var gravity: float = absf(player.gravity_z())
	var speed: float = gravity * 2.0 * sqrt(height / gravity)
	speed *= 1.0 / float(1 + wall_run.consequtive_wallruns)
	wall_running_jump_off_z_speed = maxf(speed, 10.0 * UU)
	var push: float = c.wall_running_push_away_speed_noob + c.wall_running_push_away_speed_pro_add * push_speed
	player.velocity = Vector3(saved_floor.x * push, speed, saved_floor.z * push)
	player.velocity += along * (c.wall_running_push_forward_speed_min \
		+ (1.0 - c.wall_running_push_forward_speed_min) * (1.0 - push_speed))
