class_name DodgeJumpConfig
extends MoveConfig

# The original's TdMove_DodgeJump: the sideways hop off A or D. In the
# original it is first of all a COMBAT move, used to dodge attacks. This
# project has no combat and wants it for the other half of what it does: the
# side-jump boost, whose one-off horizontal push bypasses the seven-second
# acceleration curve entirely [ME:COMMUNITY 04 §4.5].
#
# The CDO, quoted in full [ME:CONFIRMED 04 §4.5]:
#
#     BaseJumpZ           = 300      3.0 m/s   -- half of an ordinary jump
#     JumpAddXY           = 600      6.0 m/s   -- six times an ordinary jump's
#     InertiaConservation = 0.3
#     StrafeThreshold     = 0.99
#
# ALL FOUR ARE IMPLEMENTED, InertiaConservation included. It is tempting to
# read the move as "the horizontal momentum is gone and the body leaves along
# jump_add_xy alone", because a dodge thrown from a STANDSTILL leaves at
# exactly 6.0 m/s and that reading predicts it perfectly. It is wrong, and a
# standstill is the one entry speed that cannot tell the two apart. See
# inertia_conservation below for what separates them.

func _init() -> void:
	# THE THREE PROBE FLAGS ARE LEFT FALSE, AND THAT IS THE MOVE.
	#
	# [ME:CONFIRMED 11 §11.2] the capability matrix puts DodgeJump in exactly
	# one of the six capability lists -- ExitToFalling -- and in none of
	# bCheckForGrab, bCheckForVaultOver or bCheckForWallClimb. A dodge is
	# thrown sideways with nothing reaching for anything, and it is over in
	# about a third of a second; in that respect it is Coil's neighbour, not
	# Jump's.
	#
	# It reads like forgotten wiring. It is not. Nothing is assigned here for
	# the same reason CoilConfig assigns nothing: MoveConfig's defaults are
	# already neutral, and declaring a value is how a move opts into being
	# different.
	#
	# [ME:INFERRED] from play: a dodge cannot be chained to hold a sideways
	# speed nothing else reaches. Pressed again inside this, A or D plus space
	# is an ordinary jump that way -- see WalkingMove's jump branch.
	redo_move_time = 0.5

## [ME:CONFIRMED 04 §4.5] BaseJumpZ = 300 uu/s. Half of an ordinary jump's
## 630: a dodge hops, it does not launch.
@export var base_jump_z: float = 3.0

## [ME:CONFIRMED 04 §4.5] JumpAddXY = 600 uu/s. Six times the ordinary jump's
## 100, and the whole point of the move: one shot of sideways speed that no
## acceleration curve can be made to produce.
##
## SPENT ONCE, ON ENTRY, AS A WORLD VECTOR. See DodgeJumpMove.enter().
@export var jump_add_xy: float = 6.0

## [ME:CONFIRMED 04 §4.5] DodgeJumpInertiaConservation = 0.3. The share of the
## horizontal velocity the body carries into the dodge, before jump_add_xy is
## added to it.
##
## DO NOT ZERO THE HORIZONTAL VELOCITY HERE. If the momentum were dropped, the
## dodge would leave at jump_add_xy and nothing else, so EVERY dodge would
## leave at the same speed no matter what ran into it. Measured frame by frame
## off the original's debug HUD, eleven dodges, it does not: a dodge from a
## standstill leaves at 21.60 km/h and a dodge out of a 25.58 km/h run leaves
## at 26.51, and the whole set fits 0.205 * entry + 22.19 km/h to R^2 = 0.968.
## The forward component measured DURING three run-entered dodges is 4.67,
## 5.08 and 5.03 km/h where dropping the momentum predicts zero.
##
## A dodge out of a run therefore comes out FASTER than the run that entered
## it, and above the 25.92 km/h ground ceiling. That is not a symptom of the
## reading being wrong -- it is the move: the landing frame reads exactly
## 25.92, the ground clamp catching what the airborne body was allowed to
## carry, and it is why the side-jump boost is worth doing at all.
@export var inertia_conservation: float = 0.3

## [ME:CONFIRMED 04 §4.5] StrafeThreshold = 0.99, asked of
## MoveInput.strafe_axis -- the raw axis, NOT the normalised move vector.
##
## The obvious reading of 0.99 is "the input must be a pure A or D", and it is
## wrong: W+A fires a dodge in the original [ME:CONFIRMED 04 §4.5]. The
## reading that survives both facts is that the threshold is on the axis
## itself, which a key pushes full-scale no matter what else is held. DO NOT
## move this test onto move.x -- normalisation puts a keyboard diagonal at
## 0.707 and the dodge stops firing on exactly the input that was measured.
##
## [ME:INFERRED] what a PAD does here. On a stick 0.99 means "pushed nearly
## square sideways", so a diagonal push would not dodge. The original shipped
## on consoles first, which argues against that being its real behaviour: more
## likely it squares the stick's circular range, or does not gate the dodge on
## this value at all. When a pad is wired up, this is the dial to turn, and a
## measurement is what should turn it.
@export var strafe_threshold: float = 0.99
