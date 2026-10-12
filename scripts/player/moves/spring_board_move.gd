class_name SpringBoardMove
extends PhysicsMove

# The original's TdMove_SpringBoard, ported. [ME:CONFIRMED decompile]
#
# The action table asks it on a ground jump after DodgeJump and before Jump,
# once FindLedgeInFrontOfPlayer has run. CanDoMove looks for the two plants:
# the found ledge, 64 uu (+-20) above the feet and reachable within
# CheckDistanceTime at the average speed of the last quarter second; and a
# second ledge found by a box sweep from over the first, 112 uu (+-20) beyond
# it along its own face normal, standable, flat enough.
#
# Then PHYS_Flying with collision off, move input ignored, and three precise
# locations: a walk (PLM_Walk) to within 120 uu of the first plant at 1.2x the
# arrival speed, a flight to 65 uu over the first plant and one to 92 uu over
# the second, 0.2 s each by their horizontal distance. Reaching the last one
# throws the body along the pawn's facing at max(400, arrival - 100) uu/s and
# 950 uu/s up, gives collision back and sets PHYS_Falling. The move stays on
# for the rise, with its grab / vault / wall checks held off until 0.7 s after
# it started and its exit to Falling below -400 uu/s.

## TdMove_SpringBoard.SpringBoardState: 0 the walk-up, 1 and 2 the two plants,
## 3 thrown (this project's, for the presentation).
var spring_board_state: int = 0
## TdMove_SpringBoard.SavedInitialSpeed, uu/s as the original keeps it.
var saved_initial_speed: int = 200
var intermediate_foot_plant: Vector3 = Vector3.ZERO
var spring_board_foot_plant: Vector3 = Vector3.ZERO

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true
	delay_time_check_auto_moves = 0.7
	disable_movement_time = -1.0

func is_ported() -> bool:
	return true

## TdMove_SpringBoard.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move() or not player.found_ledge:
		return false
	var loc: Vector3 = player.global_position
	var feet_y: float = loc.y - player.collision_half_height()
	var ledge: Vector3 = player.move_ledge_location
	var ledge_height: float = ledge.y - feet_y
	var distance_to_step: float = Vector2(ledge.x - loc.x, ledge.z - loc.z).length()
	if distance_to_step < 20.0 * UU:
		return false
	# Max(1, int(GetAverageSpeed(0.25))), in uu/s as the original divides.
	var average_uu: int = maxi(1, int(player.get_average_speed(0.25) / UU))
	var time_to_ledge: float = (distance_to_step / UU) / float(average_uu)
	if time_to_ledge > cfg.check_distance_time:
		return false
	if absf(ledge_height - cfg.plant_1_height) >= 20.0 * UU:
		return false
	var extent := Vector3(4.0 * UU, (cfg.plant_2_max_height - cfg.plant_2_min_height) * 0.5, 4.0 * UU)
	var start := Vector3(ledge.x, feet_y + cfg.plant_2_min_height + extent.y, ledge.z)
	var end: Vector3 = start + player.facing() * cfg.plant_spacing * 1.414
	var foot: Dictionary = player.find_ledge(start, end, extent)
	if foot.is_empty():
		return false
	var foot_ledge: Vector3 = foot["ledge_location"]
	if not player.can_stand(foot_ledge + Vector3.UP * (player.default_collision_half_height() + 4.0 * UU)):
		return false
	var foot_normal: Vector3 = foot["ledge_normal"]
	if foot_normal.y < 0.8:
		return false
	if foot["feet_excluded"]:
		return false
	var plant_normal: Vector3 = PawnPhysics.safe_normal_2d(foot["move_normal"])
	var between: Vector3 = foot_ledge - ledge
	var along: Vector3 = plant_normal * between.dot(plant_normal)
	if absf(Vector2(along.x, along.z).length() - cfg.plant_spacing) >= 20.0 * UU:
		return false
	intermediate_foot_plant = ledge + Vector3.UP * 65.0 * UU
	spring_board_foot_plant = foot_ledge + Vector3.UP * 92.0 * UU
	return true

## TdMove_SpringBoard.StartMove.
func enter(_previous: StringName) -> void:
	saved_initial_speed = maxi(200, int(player.horizontal_speed() / UU))
	spring_board_state = 0
	var to_ledge: Vector3 = intermediate_foot_plant - player.global_position
	to_ledge.y = 0.0
	if to_ledge.length() > 120.0 * UU:
		set_precise_location(player.global_position + to_ledge.normalized() * (to_ledge.length() - 120.0 * UU),
			float(saved_initial_speed) * 1.2 * UU, PLM_WALK)
	else:
		reached_precise_location()
	player.collide_world = false

## TdMove_SpringBoard.ReachedPreciseLocation: the next plant, or the throw.
func reached_precise_location() -> void:
	match spring_board_state:
		0:
			set_precise_location(intermediate_foot_plant,
				_flat_distance(intermediate_foot_plant) / cfg.step_time_1, PLM_FLY)
			spring_board_state = 1
		1:
			set_precise_location(spring_board_foot_plant,
				_flat_distance(spring_board_foot_plant) / cfg.step_time_2, PLM_FLY)
			spring_board_state = 2
		2:
			var xy: float = maxf(cfg.xy_min, float(saved_initial_speed) * UU + cfg.xy_add)
			var v: Vector3 = player.facing() * xy
			v.y = cfg.jump_z
			if player.base_velocity.y > 0.0:
				v.y += player.base_velocity.y
			player.velocity = v
			player.last_jump_location = player.global_position
			player.collide_world = true
			player.set_physics(PHYS_FALLING)
			player.stop_ignore_move_input()
			use_precise_location = false
			spring_board_state = 3

func _flat_distance(to: Vector3) -> float:
	return Vector2(to.x - player.global_position.x, to.z - player.global_position.z).length()

## TdMove_SpringBoard.StopMove: collision back.
func exit() -> void:
	player.collide_world = true

## True through the two flights onto the plants. Read by CharacterAnimator.
func is_stepping() -> bool:
	return spring_board_state == 1 or spring_board_state == 2

## True once the throw has been made. Read by CharacterAnimator.
func has_launched() -> bool:
	return spring_board_state == 3

## The scripted-fit hook (CharacterAnimator._scripted_fit): the two flights,
## one window for the clip; 0 outside them.
func scripted_duration() -> float:
	return cfg.step_time_1 + cfg.step_time_2 if is_stepping() else 0.0

## The debug views draw a scripted path when a move has one; the plants'
## flights are precise locations, not a curve.
func path_debug() -> Dictionary:
	return {}
