class_name WalkingMove
extends PhysicsMove

# The original's TdMove_Walking, ported. [ME:CONFIRMED decompile] A
# TdPhysicsMove with PHYS_Walking, the PlayerWalking controller state and not
# one automatic-transition switch: every way out of walking is an action
# (MoveManager's table) or the physics (walking off an edge, a chute under
# the feet). The acceleration is PlayerWalking's (Player.player_walking_move()).

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_WALKING

func is_ported() -> bool:
	return true

## TdMove_Walking.CanDoMove: from a crouch or a slide, only with room to stand
## -- a box the default collider's size swept up by 2 H - 122 uu.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var state: StringName = player.move_manager.current_name
	if state == CROUCH or state == SLIDE:
		var start: Vector3 = player.collision_center()
		var end: Vector3 = start + Vector3.UP * (2.0 * player.default_collision_half_height() - 122.0 * UU)
		if player.phys.trace_blocked(end, start, player.collision_extent()):
			return false
	return true

## TdMove_Walking.StartMove: [ME:CONFIRMED decompile 15.4] clears the
## wall-run-jump's ledge ban. Every move that ends by setting Walking passes
## through here, which is what makes "touch the ground" end it.
func enter(_previous: StringName) -> void:
	player.illegal_ledge_timer = 0.0

## The playback-rate hook (CharacterAnimator._drive_speed): while the body is
## stepping round on the spot, the Turn90 clip plays at
## PawnConfig.turn_in_place_clip_scale; 0 otherwise leaves the speed match
## alone.
func clip_time_scale() -> float:
	return player.turn_in_place_clip_scale()
