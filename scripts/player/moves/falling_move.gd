class_name FallingMove
extends PhysicsMove

# The original's TdMove_Falling, ported. [ME:CONFIRMED decompile] PHYS_Falling,
# PlayerWalking, bCheckForGrab and bCheckForVaultOver (FallingConfig), and the
# two exits a jump does not have: an uncontrolled fall past
# FallingUncontrolledHeight and a soft landing. No wall run: Falling has no
# bCheckForWallClimb, which is the whole rule against a long drop turning into
# one.

## TdMove_Falling.PreviousMove: the move the fall came out of. Landing reads
## it to tell a jump's fall from any other.
var previous_move: StringName = &""
## TdMove_Falling.AirTime, advanced in pre_physics().
var air_time: float = 0.0
## TdMove_Falling.bCloseToGround: set once the feet are within 0.4 s of
## travel of something. Only the animation reads it in the original.
var close_to_ground: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_uncontrolled_falling = true
	check_for_soft_landing = true

func is_ported() -> bool:
	return true

## TdMove_Falling.CanDoMove. [ME:CONFIRMED decompile] Not in the first 0.8 s
## of a skill roll; out of a crouch or a slide only with room to stand 34 uu
## higher.
func can_do_move() -> bool:
	var manager = player.move_manager
	var state: StringName = manager.current_name
	if state == SKILL_ROLL:
		var roll: Move = manager.move_for(SKILL_ROLL)
		if roll != null and roll.move_active_time < 0.8:
			return false
	if state == CROUCH or state == SLIDE:
		if not player.can_stand(player.collision_center() + Vector3.UP * 34.0 * UU):
			return false
	return td_can_do_move()

## TdMove_Falling.StartMove.
func enter(_previous: StringName) -> void:
	air_time = 0.0
	close_to_ground = false
	previous_move = player.old_movement_state
	# A jump a move not yet ported launched by itself stands in for that move's
	# own jump in the original (WallRunJump, a slide's), not for TdMove_Jump.
	if previous_move == JUMP:
		var jump: Move = player.move_manager.move_for(JUMP)
		if jump != null and jump.legacy_launch_from != &"":
			previous_move = jump.legacy_launch_from
	if previous_move == WALKING:
		# Backing off an edge drops straight down: when the body moves
		# backwards and there is a body height of room below, the horizontal
		# speed is cleared. [ME:CONFIRMED decompile 15.4]
		if player.facing().dot(player.velocity) < 0.0:
			var below: Vector3 = player.global_position \
				- Vector3.UP * player.default_collision_half_height() * 2.0
			if player.can_stand(below, true):
				player.velocity.x = 0.0
				player.velocity.z = 0.0
	elif player.old_movement_state == WALL_CLIMB:
		# Off a wall climb the view the climb drew up to the ledge comes back
		# level. [ME:CONFIRMED decompile TdMove_Falling.StartMove]
		reset_camera_look(0.5)
	player.set_grounded(false)

## TdMove_Falling.TickMove: the base timer, then the close-to-ground probe --
## the feet traced 0.4 s of velocity ahead -- once per fall.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if close_to_ground:
		return
	if Vector2(player.velocity.x, player.velocity.z).length() <= 10.0 * UU:
		return
	var feet: Vector3 = player.global_position - Vector3.UP * player.collision_half_height()
	if not player.phys.line_trace(feet, feet + player.velocity * 0.4).is_empty():
		close_to_ground = true

## TdMove_Falling.PrePhysics: the TdPhysicsMove exits, then AirTime.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	air_time += delta
