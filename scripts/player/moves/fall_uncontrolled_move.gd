class_name FallUncontrolledMove
extends AirborneMove

# ControllerState = PlayerDying. Input is gone the moment this state is
# entered -- in the air, not on impact -- which is why a roll cannot save it.
# Entering is one-way: regaining height does not hand control back, because
# the original treats the outcome as already settled.

func physics_update(delta: float, _input: MoveInput) -> StringName:
	# No wish direction: the body falls, the player watches.
	apply_air_physics(delta, Vector3.ZERO)
	# No probe_transition() call at all -- the config forbids every probe, and
	# not calling it makes that structural rather than a matter of trusting
	# three booleans.
	return settle_landing(delta)

func landing_destination(_fall_height: float, _rolled: bool) -> StringName:
	player.died_from_fall.emit()
	return WALKING
