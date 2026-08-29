class_name LandingConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Landing: the lockout the
# player is put into after a hard landing taken without a roll. Landing
# thresholds themselves (which tier a fall falls into) still read straight
# off PawnConfig's Landing group -- this class only owns what happens once
# the hard-unrolled case has already been decided.

# [ME:CONFIRMED] measured 2.00 s, six hard landings, timed from the last
# Falling frame to the first Walking frame (2.03 / 2.00 / 2.00 / 2.00 / 2.00 /
# 2.02). DO NOT measure the Landing state's own span -- the original's HUD
# misreads the state name often enough to slice one lockout into several
# fragments.
@export var lockout_time: float = 2.0

## How much horizontal speed a STAGGER leaves behind, as a fraction.
##
## [ME:COMMUNITY] the original's barbed wire is a knock-down, not a wall: it
## punishes forgetting to tuck, and the arc it cuts short still carries the
## body forward and down rather than dropping it on the spot. Stopping dead
## would make a wired fence impassable, which is not what it is for.
##
## The value is PROJECT-DEFINED. Only a stagger reads it -- an ordinary hard
## landing has already been charged by Player.landing_keep_ratio() before this
## move is ever entered, and DO NOT route that through here as well.
@export var stagger_keep_ratio: float = 0.25
## PROJECT-DEFINED. The original's knee-clutch is animation root motion;
## nothing in its data describes a screen tint.
@export var tint_color: Color = Color(0.6, 0.0, 0.0)
## PROJECT-DEFINED, same reasoning as tint_color above -- there is no
## data-side counterpart to the knee-clutch's camera dip, only the animation
## itself. Radians; see CameraRig.set_landing_pitch_offset() for how this is
## combined with the ordinary look pitch.
@export var camera_pitch_offset: float = 0.35

func _init() -> void:
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # legs busy: absorbing the landing.
	# PROJECT-DEFINED, mirroring WallRunConfig's own look lock. LandingMove
	# ignores movement input outright for the whole lockout, and this pins the
	# YAW to a small forward fan to match, rather than leaving the view free
	# to spin while the body cannot act on it. Pitch is deliberately left to
	# the camera's own global limit -- see the min/max assignment below.
	constrain_look = true
	# ABSOLUTE yaw, same as WallRunConfig -- and this is what makes the yaw
	# half of the clamp mean anything at all. CameraRig.apply_look() measures
	# a relative clamp against `body.rotation.y`, i.e. against the facing the
	# player already has THIS tick, so `relative` collapses to the tick's own
	# yaw_delta and +-0.2 rad degenerates into a per-tick RATE limit of about
	# 688 deg/s -- far above any ordinary mouse sweep, i.e. no lock at all.
	# Measured against the facing captured on entry, the same +-0.2 is the
	# fan it reads as: the lockout genuinely refuses to let the view turn.
	absolute_yaw_constraint = true
	# PITCH IS DELIBERATELY NOT CLAMPED HERE. MoveConfig's own +-PI is the
	# "no clamp" value, and CameraRig.apply_look() folds a move's pitch
	# constraint into the global limit with maxf/minf -- so +-PI leaves
	# CameraConfig.pitch_limit_deg (89 deg) in sole charge, which is exactly
	# the intent. Written as the neutral sentinel rather than as a second
	# copy of 89 degrees so the two cannot drift apart; LandingConfig has no
	# reach into CameraConfig to read the real number from.
	#
	# DO NOT clamp pitch here as well: unlike yaw, the pitch half of
	# MoveConfig's clamp IS absolute, and CameraRig._pitch is not eased into
	# a new range on entry. Clamping pitch to +-0.2 here would SNAP a player
	# looking down a drop at, say, -0.7 rad to -0.2 the instant the lockout
	# starts, and set_landing_pitch_offset()'s sink would then play out from
	# that jumped-to position. Forcing the head down is camera_pitch_offset's
	# job and only its job.
	# z is roll, which apply_look() never reads; +-PI is MoveConfig's own
	# neutral, and writing 0.0 here would read as "roll is pinned".
	min_look_constraint = Vector3(-PI, -0.2, -PI)
	max_look_constraint = Vector3(PI, 0.2, PI)

## [ME:CONFIRMED 03 §3.1, 13.1] HardLandingDamage = 15, and it does NOT scale
## with height: 7 m and 9 m both cost exactly this. The player never has to
## estimate how bad a landing was -- missing the roll costs what it costs.
@export var hard_landing_damage: float = 15.0
