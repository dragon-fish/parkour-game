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
		# Source: 02 §2.4 `JumpAddXY = 100` uu/s. ⚠️ Inferred as an ADDITION
		# along the facing at take-off (whether it adds or sets a minimum is
		# unverified); taking off is itself a small forward commitment. Same
		# boost as the two grounded jump sites (WalkingMove, SlideMove) --
		# this is structurally the same take-off, just consumed a tick or two
		# late by the coyote window, and a player cannot tell the difference
		# between the two paths, so neither can the boost.
		var facing: Vector3 = -player.global_transform.basis.z
		player.velocity.x += facing.x * config.pawn.jump_add_xy
		player.velocity.z += facing.z * config.pawn.jump_add_xy
		player.set_grounded(false)
		return JUMP

	apply_air_physics(delta, player.wish_direction(input))

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	return settle_landing(delta)
