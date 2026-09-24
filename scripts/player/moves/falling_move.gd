class_name FallingMove
extends AirborneMove

# [ME:CONFIRMED 11 §11.2] TdMove_Falling is airborne but not a launch: it has
# no bCheckForWallClimb, so it cannot start a wall run, and it is one of only
# six states that can hand off to uncontrolled falling.

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
		player.add_jump_nudge(input)
		player.set_grounded(false)
		return JUMP

	apply_air_physics(delta, player.wish_direction(input))

	# [ME:CONFIRMED 11 §11.2] six states hold bCheckExitToUncontrolledFalling
	# and not one of them is a launch (I2). See lose_control().
	var lost: StringName = lose_control()
	if lost != KEEP:
		return advance_and_hand_off(lost)

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	return settle_landing(delta)
