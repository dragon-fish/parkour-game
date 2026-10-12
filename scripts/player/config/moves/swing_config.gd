class_name SwingConfig
extends MoveConfig

# The original's TdMove_Swing: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Swing]. Lengths in metres, speeds in m/s, angles in radians.

func _init() -> void:
	# [ME:CONFIRMED ini] bCheckForGrab, bCheckForVaultOver, bCheckForWallClimb
	# are set -- and dead: the swing keeps Velocity at zero, and
	# CheckAutoMoves returns at once for a body that is not moving
	# [ME:CONFIRMED decompile N5 §16].
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# MG_TwoHandsBusy: both hands on the bar.
	allows_turn = false
	# A hazard's hit knocks the body off. See MoveConfig.hit_knocks_off.
	hit_knocks_off = true
	holds_world_path = true

## [ME:CONFIRMED ini] SwingPendulumLength = 120 uu: the pawn's centre hangs
## this far below the grip.
@export var pendulum_length: float = 1.2
## [ME:CONFIRMED ini] ExitVelocityModifier = 600 uu/s. The WHOLE exit speed
## -- it replaces the swing's zero velocity, scaled by cos(JumpAngle).
@export var exit_velocity_modifier: float = 6.0
## [ME:CONFIRMED ini] SwingAngleTimingOffset = 1.0 rad: JumpAngle =
## min(pi/2, SwingAngle - this), and the jump needs JumpAngle > -pi/4.
@export var swing_angle_timing_offset: float = 1.0
## [ME:CONFIRMED ini] SwingExitGravityModifier 0.75 for
## SwingExitGravityModifierTime 0.70 s, on the physical exit only.
@export var exit_gravity_modifier: float = 0.75
@export var exit_gravity_modifier_time: float = 0.7
## [ME:CONFIRMED decompile] MaxSwingVelocity = 4.25 rad/s, capped by
## cos(angle) at the extremes.
@export var max_swing_velocity: float = 4.25
## [ME:CONFIRMED decompile] AnimBlendTime = 0.15 s: the pull onto the arc, the
## turn to the swing direction and the camera reset all take it.
@export var anim_blend_time: float = 0.15

## How much of the swing angle the MODEL leans by, about the bar. The
## original drives a SwingControl bone by the angle; this project leans the
## body. Presentation only.
@export var model_pitch_follow: float = 1.0
## Metres the eye slides forward, and rises, at a full forward lean (scaled by
## sin(angle), forward swings only), so the leaning chest does not sweep
## through a fixed eye. Presentation only. DO NOT leave both at 0.
@export var eye_forward_lean: float = 0.1
@export var eye_lift_lean: float = 0.25
