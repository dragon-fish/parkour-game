class_name SoftLandingMove
extends AirborneMove

# [ME:CONFIRMED 12 §12.5] The fall that was going to be fatal and lands on
# something soft instead. FallingMove decides between this and
# FallUncontrolledMove once, at the tick the lethal height is crossed.
#
# THE PAD DOES NOT HAND CONTROL BACK. It changes the ENDING, not the fall:
# input is gone here exactly as it is in an uncontrolled fall, the body is a
# passenger the whole way down, and what the pad buys is arriving alive. A
# rescue that also returned the controls would make the lethal height mean
# nothing wherever a pad was in reach -- the player would simply fly on.
#
# Nothing here desaturates or blurs the screen. That is FallUncontrolledMove's
# and it says "you are dying"; a body about to be caught is not.

func enter(_previous: StringName) -> void:
	# The gate, not a look constraint. See FallUncontrolledMove's own note:
	# the camera is driven from Player._physics_process(), so ignoring the
	# input argument below is not on its own enough to stop the view spinning
	# all the way down.
	player.lock_input()

func physics_update(delta: float, _input: MoveInput) -> StringName:
	# Vector3.ZERO, not the wish direction: there is no steering out of this.
	apply_air_physics(delta, Vector3.ZERO)
	return settle_landing(delta)

## Always the hard landing, never the roll.
##
## The default would reach the same answer by arithmetic -- this fall is past
## the lethal height, which is well past hard_landing_height -- but it would
## reach it via `rolled`, and a roll consumed from a buffer filled before
## control was lost would silently discount a landing the player had no hand
## in. Said outright instead: you are put down hard, and getting up takes the
## moment it takes.
func landing_destination(_fall_height: float, _rolled: bool) -> StringName:
	return LANDING

func exit() -> void:
	# Released by the state that closed it, the same discipline
	# FallUncontrolledMove keeps: LandingMove closes it again for its own
	# lockout on the very next tick.
	player.unlock_input()

## Nothing. The pad is what the fall cost.
##
## The lockout still runs -- being caught is not being let off -- but the bar
## is untouched, which is the whole difference between landing on a pad and
## landing on the floor beside it.
func landing_damage(_fall_height: float, _rolled: bool) -> float:
	return 0.0
