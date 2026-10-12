class_name SwingJumpMove
extends PhysicsMove

# The original's TdMove_SwingJump, ported. [ME:CONFIRMED decompile script
# TdMove_SwingJump, N5 §16]
#
# The flight off a bar. Swing.JumpOff has already set the velocity -- the arc's
# tangent at 600 cos(JumpAngle) -- and the 0.75 / 0.7 s gravity, unless it
# found another bar ahead (target_volume): then this move flies the body to
# it, PHYS_Flying on a precise location (PLM_SimJump at distance / 0.9 s) under
# a 0.73 gravity for 0.75 s, and drops back to PHYS_Falling after 0.9 s.

## TdMove_SwingJump.TargetVolume: the bar ahead, or null. Set by Swing.JumpOff
## and never cleared here.
var target_volume: InterestLine = null

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	# [ME:CONFIRMED decompile] bCheckExitToFalling at the default -400 uu/s.
	check_exit_to_falling = true

func is_ported() -> bool:
	return true

func can_do_move() -> bool:
	return td_can_do_move()

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
	if target_volume == null or not is_instance_valid(target_volume):
		return
	player.gravity_modifier = cfg.gravity_modifier
	player.gravity_modifier_timer = cfg.gravity_modifier_timer
	player.set_physics(PHYS_FLYING)
	var target: Vector3 = SwingMove.volume_location(target_volume)
	var to: Vector3 = target - player.global_position
	var distance_2d: float = Vector2(to.x, to.z).length()
	set_precise_location(target + PawnPhysics.safe_normal(to) * cfg.target_offset_along \
		+ Vector3.UP * cfg.target_offset_up, distance_2d / 0.9, PLM_SIM_JUMP)
	set_timer(0.9)

func on_timer() -> void:
	player.set_physics(PHYS_FALLING)
