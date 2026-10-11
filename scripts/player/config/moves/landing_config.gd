class_name LandingConfig
extends MoveConfig

# The original's TdMove_Landing defaults. The landing heights themselves
# (SkillRollLandingHeight, SoftLandingHeight, HardLandingHeight) are
# PawnConfig's.

## [ME:CONFIRMED decompile 15.6, ini] LandingSpeedReduction = 65 uu/s: after a
## jump's fall the landing caps the horizontal speed at the jump's take-off
## speed (TdMove_Jump.PreJumpMomentum) minus this. See
## LandingMove.subtract_landing_speed().
@export var landing_speed_reduction: float = 0.65

## How long a hard landing (and a landing on a soft object) holds the body,
## seconds. The original's is the FallingLandHard animation's own length,
## ended by OnCustomAnimEnd; this project has not got that animation, so the
## length is measured instead. [ME:CONFIRMED] 2.00 s, six hard landings, timed
## from the last Falling frame to the first Walking frame (2.03 / 2.00 / 2.00 /
## 2.00 / 2.00 / 2.02).
@export var lockout_time: float = 2.0

## How much horizontal speed a level's STAGGER leaves behind, as a fraction.
## This project's own hazard, not the original's landing.
##
## [ME:COMMUNITY] the original's barbed wire is a knock-down, not a wall: the
## arc it cuts short still carries the body forward and down rather than
## dropping it on the spot. The value is PROJECT-DEFINED.
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
	allows_turn = false

## [ME:CONFIRMED 03 §3.1, 13.1] HardLandingDamage = 15, and it does NOT scale
## with height: 7 m and 9 m both cost exactly this.
@export var hard_landing_damage: float = 15.0
