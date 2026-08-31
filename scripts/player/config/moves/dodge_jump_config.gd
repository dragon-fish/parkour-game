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
# InertiaConservation IS NOT IMPLEMENTED, and is not declared below as a dial
# nobody reads. Nothing survives the launch for it to scale: [ME:CONFIRMED 04
# §4.5] the horizontal momentum is gone on the tick the dodge starts, and the
# body leaves along jump_add_xy and nothing else. The 14.4 km/h a dodge is
# measured to land on is where the CEILING goes -- the speed the run rebuilds
# from after touchdown -- not a speed the airborne body keeps. Both halves are
# Player.dodge_launch(), and its own note has the two wrong readings that came
# before this one.

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
	pass

## [ME:CONFIRMED 04 §4.5] BaseJumpZ = 300 uu/s. Half of an ordinary jump's
## 630: a dodge hops, it does not launch.
@export var base_jump_z: float = 3.0

## [ME:CONFIRMED 04 §4.5] JumpAddXY = 600 uu/s. Six times the ordinary jump's
## 100, and the whole point of the move: one shot of sideways speed that no
## acceleration curve can be made to produce.
##
## SPENT ONCE, ON ENTRY, AS A WORLD VECTOR. See DodgeJumpMove.enter().
@export var jump_add_xy: float = 6.0

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
