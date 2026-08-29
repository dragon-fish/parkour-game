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
		player.velocity += player.jump_add_velocity(input)
		player.set_grounded(false)
		return JUMP

	apply_air_physics(delta, player.wish_direction(input))

	# [ME:CONFIRMED 11 §11.2] Only Falling may hand off here: six states hold
	# bCheckExitToUncontrolledFalling and not one of them is a launch (I2).
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		# [ME:INFERRED 12 §12.5] THE PAD IS ASKED ABOUT BEFORE THE DEATH, NOT
		# AFTER. The original checks bCheckForSoftLanding from inside
		# FallingUncontrolled, so a doomed fall there can still be reprieved --
		# but this project's FallUncontrolledMove.enter() starts a ragdoll and
		# stops the capsule on its first tick, and pulling a body back out of
		# that is far harder than never putting it in.
		if not _falls_somewhere_soft(delta):
			return advance_and_hand_off(FALL_UNCONTROLLED)

	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	return settle_landing(delta)

## How often the arc is re-walked while the body is past the lethal height.
##
## NOT ONCE. Falling still has air control, so a player can steer off a pad
## after being reprieved -- or onto one after being told they were doomed,
## except that answer takes them straight out of this state. Asked every tick
## instead, a deep fall would walk the arc sixty times a second for an answer
## that cannot change much in 17 ms.
const RESCUE_RECHECK := 0.2

var _rescue_owed: float = 0.0
var _rescued: bool = false

func enter(previous: StringName) -> void:
	super(previous)
	_rescue_owed = 0.0
	_rescued = false

## Whether the arc the body is on ends on something that absorbs a fall.
func _falls_somewhere_soft(delta: float) -> bool:
	_rescue_owed -= delta
	if _rescue_owed > 0.0:
		return _rescued
	_rescue_owed = RESCUE_RECHECK
	var hit: Dictionary = player.probes.predicted_landing(player.velocity)
	_rescued = not hit.is_empty() and Probes.is_soft(hit.get("collider"))
	return _rescued
