class_name JumpMove
extends AirborneMove

# The original's TdMove_Jump: the airborne stretch you still own. It is the
# only phase that may start a wall run -- seven states hold bCheckForWallClimb
# and every one of them is a deliberate launch (11 §11.2). A long descent that
# merely brushes a building is NOT one of them.

func physics_update(delta: float, input: MoveInput) -> StringName:
	apply_air_physics(delta, player.wish_direction(input))

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	# Handing off downward is checked BEFORE this tick's landing settle, so a
	# tick that both crosses the threshold and touches down lands as Falling
	# would -- the descent is what the landing is judged on.
	if player.velocity.y <= config.pawn.enter_to_falling_z_speed:
		player.set_grounded(false)
		return FALLING

	return settle_landing(delta)
