class_name SwingConfig
extends MoveConfig

# The original's TdMove_Swing / TdMove_SwingJump (05 §5.4, §5.5b), plus the
# owner's own ME measurements for the two noob compensations: magnetic
# attachment, and a lenient fixed-angle exit jump.

func _init() -> void:
	# A hazard's hit knocks the body off. See MoveConfig.hit_knocks_off.
	hit_knocks_off = true
	# Rides a world-space InterestLine target. See MoveConfig.holds_world_path.
	holds_world_path = true
	allows_turn = false  # both hands on the bar (MG_TwoHandsBusy)
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-deg_to_rad(80.0), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(80.0), deg_to_rad(90.0), PI)
	# Per-LINE cooldown (Player.note_line_left), not per move name -- same
	# decision the zipline's own measurement forced.
	redo_move_time = 0.0

## Q turns the body round on the bar, but only once the swing has all but
## stopped: while the speed it would pass the bottom at is below this, m/s. See
## SwingMove.swing_bottom_speed().
##
## THE SWING'S WHOLE ENERGY, NOT THIS TICK'S ANGULAR VELOCITY. That one passes
## through zero at every apex, so a gate on it opened for a moment at the top
## of every swing, however big.
##
## [ME:INFERRED] from play that the gate exists; the value is a guess to tune.
@export var turn_max_swing_speed: float = 0.6
## How long the turn round on the bar takes, seconds.
## [ME:INFERRED] from play: about two seconds.
@export var turn_time: float = 2.0

## [ME:CONFIRMED 05 §5.4, §5.5b.1] SwingPendulumLength = 120 uu.
## [ME:DERIVED] quarter-period = (2*PI*sqrt(pendulum_length / gravity)) / 4 =
## 0.43 s at gravity 16.0 -- why a first forward swing already reaches full
## amplitude, without needing to build it up over several passes.
@export var pendulum_length: float = 1.2
## [ME:CONFIRMED 05 §5.5b.3] MaxSwingVelocity = 4.25 -- the swing HAS a cap
## (the zipline does not).
@export var max_swing_velocity: float = 4.25
## [ME:CONFIRMED 05 §5.5b.3] ExitVelocityModifier = 600 uu: the launch speed
## of the exit jump.
@export var exit_speed: float = 6.0
## MVP RULING: the exit angle is FIXED, always forward at this incline above
## the horizontal, rather than derived from the swing's own state.
@export var exit_angle_deg: float = 45.0
## PROJECT-DEFINED, deliberately lenient: the jump is allowed once the
## FORWARD angular velocity (radians per second) exceeds this. DELIBERATELY
## LOW so the window is wide.
@export var jump_min_omega: float = 0.8
## OWNER-FELT grace: once the window has been open, it STAYS open this many
## seconds -- covering the forward apex where omega crosses zero, so the jump
## still fires there even though angular velocity is near zero and about to
## reverse. The feel-side stand-in for the CDO's unmeasured
## SwingAngleTimingOffset.
@export var jump_grace_time: float = 0.35
## PROJECT-DEFINED. Angular acceleration W/S pumping adds when pushed WITH
## the current swing direction. Tuned by feel.
@export var pump_accel: float = 3.0
## The magnet: how long the catch takes to pull the body onto the chain. Same
## number and same feel as the zipline's own fade.
@export var fade_in_time: float = 0.1

## Metres per second the body is pulled onto the line, once the catch is made
## from further out than fade_in_time's worth.
##
## fade_in_time above is the FLOOR and stays the original's: a catch from
## within arm's reach still lands in exactly that. This is what stops a wider
## reach turning into a harder yank -- reaching further takes longer instead.
## A dial, judged by eye; nothing in the original names it.
@export var catch_speed: float = 10.0
## [ME:CONFIRMED 05 §5.5b.2] SwingExitGravityModifier = 0.75 for
## SwingExitGravityModifierTime = 0.70 s (TdMove_SwingJump repeats nearly the
## same pair). Fed to Player.apply_gravity_window() on BOTH exits.
@export var exit_gravity_multiplier: float = 0.75
@export var exit_gravity_time: float = 0.7
## PROJECT-DEFINED: how long the bar just left refuses a re-catch.
@export var same_line_redo_time: float = 1.0

## OWNER-FELT: catching the bar from a standstill jump must not swing wildly.
## The catch hands out up to 25 degrees of free amplitude (the magnet clamp)
## plus the full arrival momentum, and an undamped pendulum keeps whatever it
## is given forever. Three dials address this: the residual angle the magnet
## leaves, how much of the arrival momentum the hands absorb, and a light
## damping so an un-pumped swing settles -- the player must pump to KEEP
## swinging.
@export var entry_max_theta_deg: float = 8.0
@export var entry_omega_scale: float = 0.5
@export var damping: float = 0.4

## How much of the pendulum angle the MODEL leans by (about the bar).
## [ME:INFERRED] how ME sells swing amplitude: mainly by letting the player
## see their own body lean in the camera -- the body tilts along the chain
## and the camera stays FREE (no forced pitch; ME does not sync the view to
## the swing).
@export var model_pitch_follow: float = 1.0

## OWNER-FELT dial: metres the EYE slides forward at a full-forward lean
## (scaled by sin(theta), forward swings only). DO NOT leave this at 0: the
## leaning chest sweeps through the fixed eye without it.
@export var eye_forward_lean: float = 0.1
## ...and metres it rises at a full-forward lean. Both axes ship as dials,
## since the right compensation direction (forward vs. up) was not obvious in
## advance; zero either to isolate.
@export var eye_lift_lean: float = 0.25
