class_name Turn180InAirMove
extends AirborneMove

# The original's TdMove_180TurnInAir: Q in mid-air, off no wall. A state of
# its own because it is a passenger's state, not a turn tacked onto a fall.
#
# [ME:INFERRED] from play: after the turn the keys do nothing until the feet
# arrive, as in an uncontrolled fall or a soft landing, and the flight keeps
# the speed it had. [ME:CONFIRMED 11 §11.2] it can lose control into
# FallUncontrolled or SoftLanding and can do nothing else -- no ledge, no
# vault, no wall.
#
# Turned round while travelling the way it WAS facing, the flight ends on the
# body's back (Player.pending_back_landing), and settle_landing() charges the
# drop the same as any other.

## Below this a body is not "going forward", it is drifting: a standing jump
## has a few centimetres a second of its own. Not a speed gate -- any real
## forward jump clears it many times over.
const FORWARD_TRAVEL_M_S := 0.5

var _turn: HalfTurn = HalfTurn.new()
var _elapsed: float = 0.0

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_turn.begin(player.rotation.y)
	player.set_grounded(false)
	var was_facing := Vector3(-sin(_turn.from), 0.0, -cos(_turn.from))
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if travel.dot(was_facing) > FORWARD_TRAVEL_M_S:
		player.pending_back_landing = true

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta
	_turn.advance(player, _elapsed / maxf(cfg.turn_time, 0.001))
	# NO INPUT: a zero wish leaves the flight to gravity alone.
	apply_air_physics(delta, Vector3.ZERO)

	var lost: StringName = lose_control()
	if lost != KEEP:
		return advance_and_hand_off(lost)

	var landed: StringName = settle_landing(delta)
	# Touching down mid-spin finishes the spin rather than cutting it.
	if landed != KEEP:
		_turn.advance(player, 1.0)
	return landed
