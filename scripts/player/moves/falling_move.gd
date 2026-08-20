class_name FallingMove
extends AirborneMove

# The original's TdMove_Falling: airborne, but no longer a launch. It cannot
# start a wall run (no bCheckForWallClimb), and it is one of only six states
# that can hand off to uncontrolled falling (11 §11.2).

func physics_update(delta: float, input: MoveInput) -> StringName:
	# Coyote time lives HERE and not in JumpMove: it exists for a player who
	# walked off a ledge without jumping, which is exactly the state Falling
	# describes. Player.consume_jump() already gates on the timer, so a jump
	# buffered just after walking off a ledge still fires here.
	if player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z
		# Same nudge as the two grounded take-off sites: a coyote jump is
		# structurally the same take-off, just consumed a tick or two late,
		# and a player cannot tell the two paths apart.
		player.velocity += player.jump_add_velocity(input)
		player.set_grounded(false)
		return JUMP

	apply_air_physics(delta, player.wish_direction(input))

	# Only Falling may hand off here: six states hold
	# bCheckExitToUncontrolledFalling and not one of them is a launch (I2).
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		player.set_grounded(false)
		return FALL_UNCONTROLLED

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	return settle_landing(delta)
