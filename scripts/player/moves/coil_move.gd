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
	player.coil_capsule_held = true
	# The landing that ends this airborne stretch is a coil's landing, however
	# long after the tuck it comes. See Player.last_landing_coiled.
	player.coiled_since_ground = true
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

	# Coil is one of the six states holding bCheckExitToUncontrolledFalling
	# (11 §11.2), and the only one of them that is not simply a fall: tucking
	# up does not save a player who has already dropped too far.
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		return advance_and_hand_off(FALL_UNCONTROLLED)

	# ✅ CoilTime. The legs stay tucked for all of it -- the owner's "后摇" --
	# so there is nothing to unwind here; the clock simply runs out.
	#
	# 📌 LANDING IS settle_landing()'s JOB, UNCHANGED AND UNHELPED. It reads
	# is_on_floor() off the SHRUNKEN capsule, whose floor sits half a shrink
	# above where the feet really are -- so a tucked body touches down later
	# than an upright one. That is not an error to correct: it is what "the
	# legs are up" MEANS, and it is the same half-shrink that carries the body
	# over a gap's far lip instead of catching on it.
	if _elapsed >= cfg.duration:
		return advance_and_hand_off(FALLING)

	# No probe_transition() call, and its absence is the move. CoilConfig
	# leaves all three probe flags false, so routing through it would do
	# nothing -- but calling it anyway would read as "coil probes like every
	# other airborne state, it just happens to find nothing". It does not
	# probe. See CoilConfig's own note, and tests/test_coil.gd.
	return settle_landing(delta)

## Where a landing out of a coil leads: CROUCH, and let the crouch decide when
## to stand.
##
## ⚠️ THE MOVE DOES NOT ASK WHETHER IT CAN STAND UP, AND MUST NOT.
##
## An earlier version watched the ground every tick and ended the tuck as soon
## as a standing capsule would no longer fit. ✅ THE OWNER KILLED IT, and the
## reason is the whole purpose of the move: "你不要自作主张检测胶囊下方有没有
## 地面并提前站起来，这样违背动作的设计了，它就是用来通过不蜷缩无法通过的地方，
## 比如越过会受伤的铁丝网...还有个速通技巧就是使用这个技巧直接精准跳进通风管道，
## 你随手加的检测会让角色无法跳进去".
##
## "A standing capsule does not fit here" is TRUE of every place a coil is for.
## Razor wire, a duct mouth, any gap only a tucked body clears -- the check
## fired hardest exactly where putting the legs down is worst.
##
## ✅ THE OWNER'S OWN ANSWER, and it needs no detection at all: "不能恢复站立，
## 和翻滚和滑铲一样，如果当时无法站立就转蹲下；比如缩腿跳进通风管道". Both of
## those moves already end this way (SkillRollMove and SlideMove each hand to
## CROUCH when the head is blocked), and CrouchMove already knows how to wait:
## it stands only once the key is released AND has_headroom() agrees, and stays
## down indefinitely otherwise.
##
## 📌 HANDED OVER UNCONDITIONALLY rather than gated on has_headroom() here,
## which would be the obvious way to copy the two precedents. It cannot work
## from this side: the capsule is still centre-anchored at this instant, so its
## floor is half a shrink above the real feet and a standing overlap test
## reads the ground it is resting on as a blocked head -- false everywhere,
## including open sky. Crouch is free to enter (crouch_capsule_height and
## CoilConfig.capsule_height are the same number), it re-anchors the capsule on
## the way in, and on open ground it hands straight back to Walking on the very
## next tick. So the cost of not asking is one frame of Crouch, and the benefit
## is that the question gets asked by the code that can answer it.
##
## 📌 WHAT THE HAND-OFF BUYS IS NOT THE CAPSULE. Measured by removing this line
## and landing in a duct: the body stays compressed anyway, because
## request_standing_capsule() correctly refuses to grow into the roof. What it
## became instead was WALKING at a standing speed cap inside a crouched
## capsule -- a body shuffling through a duct at running pace. The capsule was
## never the part that needed handing over; the speed modifier and the stand-up
## rule were.
func landing_destination(fall_height: float, rolled: bool) -> StringName:
	var destination := super(fall_height, rolled)
	return CROUCH if destination == WALKING else destination

## THE CAPSULE IS NOT GIVEN BACK HERE. The tuck is over; the shrink is not.
## [ME:CONFIRMED by the collision-box visualiser] the capsule stays half height
## from the coil until the landing -- CoilTime ends the pose, not the shape.
## It is what lets a coil after a springboard make a duct mouth the whole
## flight away; given back at CoilTime, the body is full height again long
## before it arrives. See Player.coil_capsule_held and release_coil_capsule().
func exit() -> void:
	pass

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
