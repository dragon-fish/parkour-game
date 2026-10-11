class_name Turn180InAirMove
extends AirborneMove

# The original's TdMove_180TurnInAir: Q in mid-air, off no wall. A state of
# its own because it is a passenger's state, not a turn tacked onto a fall.
#
# ONLY FROM A JUMP. [ME:INFERRED] from play: once the body is falling, Q does
# nothing -- the airborne moves other than JumpMove refuse it through their
# own MoveConfig.allows_turn.
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

func _init() -> void:
	# [ME:CONFIRMED decompile] TdMove_180TurnInAir's PawnPhysics. This move still drives the
	# body itself; the mode is what the original's checks and the fall height
	# read while it runs.
	pawn_physics = PHYS_FALLING

## [ME:CONFIRMED decompile] TdMove_180TurnInAir.CanDoMove: not from a soft
## landing, and only while travelling roughly the way the body faces
## (Normal(facing) . Normal(Velocity) >= 0.2).
func can_do_move() -> bool:
	if player.move_manager.current_name == SOFT_LANDING:
		return false
	var v_dir: Vector3 = player.velocity.normalized() if player.velocity.length_squared() > 0.0 else Vector3.ZERO
	if player.facing().dot(v_dir) < 0.2:
		return false
	return super.can_do_move()

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
