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

	# [ME:CONFIRMED 11 §11.2] Only Falling may hand off here: six states hold
	# bCheckExitToUncontrolledFalling and not one of them is a launch (I2).
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		# [ME:CONFIRMED 12 §12.5] ONE CHECK, AT THE MOMENT CONTROL IS LOST, and
		# never again. The original asks whether the arc ends on something soft
		# exactly here; what it buys is which state the body loses control INTO,
		# not whether it loses control at all. A pad does not hand the fall back
		# -- the player is a passenger either way, and the difference shows up on
		# impact.
		#
		# Asked before the death rather than from inside it, unlike the original,
		# because FallUncontrolledMove.enter() starts a ragdoll and stops the
		# capsule on its first tick and pulling a body back out of that is far
		# harder than never putting it in.
		var arc: Dictionary = player.probes.predicted_landing(player.velocity)
		if not arc.is_empty() and Probes.is_soft(arc.get("collider")):
			return advance_and_hand_off(SOFT_LANDING)
		return advance_and_hand_off(FALL_UNCONTROLLED)

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	return settle_landing(delta)
