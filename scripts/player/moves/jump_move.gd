class_name JumpMove
extends AirborneMove

# [ME:CONFIRMED 11 §11.2] TdMove_Jump: the airborne stretch you still own. It
# is the only phase that may start a wall run -- seven states hold
# bCheckForWallClimb and every one of them is a deliberate launch. A long
# descent that merely brushes a building is NOT one of them.

## Which wall this jump was kicked off, or 0 for an ordinary jump.
##
## Lets CharacterAnimator tell a wall-kick jump from an ordinary one and pick
## the WallRun_Jump_L/R clip instead of the plain jump animation, the same way
## it reads GrabMove.is_mantling() and SpeedVaultMove.is_scramble().
var _kick_side: int = 0

func kick_side() -> int:
	return _kick_side

## DO NOT read wall_side here -- use recent_wall_side. MoveManager exits the
## old move before entering the new one, and WallRunMove.exit() clears
## wall_side, so by the time this runs the live one is already zero;
## recent_wall_side is the one kept for exactly this kind of question.
func enter(previous: StringName) -> void:
	_kick_side = player.recent_wall_side if previous == WALL_RUN else 0

func physics_update(delta: float, input: MoveInput) -> StringName:
	apply_air_physics(delta, player.wish_direction(input))

	# BEFORE the probes -- see coil_transition().
	if coil_transition() == COIL:
		return advance_and_hand_off(COIL)

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	# Handing off downward is checked BEFORE this tick's landing settle, so a
	# tick that both crosses the threshold and touches down lands as Falling
	# would -- the descent is what the landing is judged on.
	if player.velocity.y <= config.pawn.enter_to_falling_z_speed:
		return advance_and_hand_off(FALLING)

	return settle_landing(delta)
