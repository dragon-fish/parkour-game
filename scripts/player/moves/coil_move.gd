class_name CoilMove
extends AirborneMove

# The original's TdMove_Coil: the legs come up under the chin for half a
# second. GBA_Crouch's fifth outlet (05 §5.2), and the last row of
# walking_move.gd's table to get any code behind it.
#
# AN AirborneMove SUBCLASS AND NOT A SCRIPTED ONE. A coil does not drive the
# body anywhere -- the jump's own arc carries on underneath it, unchanged. What
# the move owns is the CAPSULE and the PROBE SET, and both of those are
# expressed as data (CoilConfig), so what is left here is a clock and one piece
# of care about landing.

## Seconds since the tuck began. Drives both the ease and the timeout.
var _elapsed: float = 0.0

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	player.set_grounded(false)
	# Shrunk on the entry tick rather than waiting for the first
	# physics_update(): a coil taken to clear something is being asked for
	# BECAUSE of what is coming, and a tick of full-height capsule is a tick of
	# exactly the collision the player pressed the key to avoid.
	_apply_capsule()

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta
	_apply_capsule()
	apply_air_physics(delta, player.wish_direction(input))

	# THE STANDING FEET, NOT THE COILED ONES, AND THIS IS THE WHOLE OF THE
	# LANDING CARE. The capsule is shrunk about its centre, so its floor sits
	# half a shrink ABOVE where the body's feet really are; is_on_floor() would
	# therefore let the body sink that far into the ground before reporting a
	# landing, and the restore -- which grows the capsule downward again --
	# would finish the job of burying it. See Player.set_centred_capsule_height()
	# for the same failure caught in play once already.
	#
	# Asked before this tick's own move_and_slide(), matching how the vault and
	# grab checks in AirborneMove.probe_transition() are ordered.
	if not player.fits_standing_at(_standing_feet()):
		# Returned BEFORE settle_landing() runs, so the tick that touches down
		# does so at full height and lands like any other.
		# set_, NOT request_, and the difference is the whole bug this branch
		# was written to avoid. request_standing_capsule() honours the roof by
		# REFUSING a restore that does not fit and owing it instead -- and by
		# the time the standing feet have reached a floor, the standing capsule
		# no longer fits, because its floor is exactly what they reached. The
		# refusal is then permanent: a body resting on the ground never rises
		# on its own, so has_headroom() stays false forever and the player is
		# left walking around inside a coiled capsule. Measured, before this
		# line said set_: the body settled at y 0.451 -- half a shrunken
		# capsule -- and stayed there.
		#
		# Growing DOWNWARD into the floor is safe in a way growing UPWARD into
		# a ceiling is not: settle_landing()'s own move_and_slide(), two lines
		# below, depenetrates it on this very tick. That asymmetry is why the
		# deferred path is right for exit() and wrong for here.
		player.set_capsule_height(player.standing_height())
		# THE TUCK IS OVER EITHER WAY, and returning KEEP here was a real bug
		# for one revision: the standing feet arrive half a shrink before the
		# COILED ones do, so settle_landing() can quite correctly report no
		# landing yet -- and staying in the move meant the next tick shrank the
		# capsule straight back down, restored it again, and strobed until the
		# shrunken capsule finally reached the floor. The feet having arrived
		# is the end of the coil; whether this same tick also produced a
		# landing is settle_landing()'s business, not this branch's.
		var landed := settle_landing(delta)
		return FALLING if landed == KEEP else landed

	# Coil is one of the six states holding bCheckExitToUncontrolledFalling
	# (11 §11.2), and the only one of them that is not simply a fall: tucking
	# up does not save a player who has already dropped too far.
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		return advance_and_hand_off(FALL_UNCONTROLLED)

	# ✅ CoilTime. The legs stay tucked for all of it -- the owner's "后摇" --
	# so there is nothing to unwind here; the clock simply runs out and exit()
	# gives the capsule back.
	if _elapsed >= cfg.duration:
		return advance_and_hand_off(FALLING)

	# No probe_transition() call, and its absence is the move. CoilConfig
	# leaves all three probe flags false, so routing through it would do
	# nothing -- but calling it anyway would read as "coil probes like every
	# other airborne state, it just happens to find nothing". It does not
	# probe. See CoilConfig's own note, and tests/test_coil.gd.
	return settle_landing(delta)

func exit() -> void:
	# request_, not set_: a coil that ended inside a gap it was threading has
	# no room to stand up in yet, and Player already owns the machinery for
	# owing a restore until there is.
	player.request_standing_capsule()

## Where the feet would be at full height. The body's origin is the capsule's
## own centre (see player.tscn), so this is one standing half-height below it,
## whatever the live capsule has been shrunk to.
func _standing_feet() -> Vector3:
	return player.global_position - Vector3.UP * player.standing_height() * 0.5

## Eases the capsule down to CoilConfig.capsule_height across boost_duration,
## then holds it there for the rest of `duration`.
##
## ✅ HeightBoostDuration is the EASE and CoilTime is the HOLD -- the reading
## that makes the original's two durations stop looking redundant. See
## CoilConfig.boost_duration.
func _apply_capsule() -> void:
	var eased: float = 1.0
	if cfg.boost_duration > 0.0:
		eased = minf(_elapsed / cfg.boost_duration, 1.0)
	player.set_centred_capsule_height(
		lerpf(player.standing_height(), cfg.capsule_height, eased))
