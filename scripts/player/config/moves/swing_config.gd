class_name SwingConfig
extends MoveConfig

# The original's TdMove_Swing / TdMove_SwingJump (05 §5.4, §5.5b), plus the
# owner's own ME measurements for the two noob compensations: magnetic
# attachment, and a lenient fixed-angle exit jump.

func _init() -> void:
	allows_turn = false  # both hands on the bar (MG_TwoHandsBusy)
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-deg_to_rad(80.0), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(80.0), deg_to_rad(90.0), PI)
	# Per-LINE cooldown (Player.note_line_left), not per move name -- same
	# decision the zipline's own measurement forced.
	redo_move_time = 0.0

## ✅ SwingPendulumLength = 120 uu.
@export var pendulum_length: float = 1.2
## ✅ MaxSwingVelocity = 4.25 -- the swing HAS a cap (the zipline does not).
@export var max_swing_velocity: float = 4.25
## ✅ ExitVelocityModifier = 600 uu: the launch speed of the exit jump.
@export var exit_speed: float = 6.0
## ⚠️ OWNER MVP RULING: the exit angle is FIXED -- "飞出去的角度每次都一样，
## MVP我们可以先预设为每次都往前方斜45°飞". Degrees above the horizontal.
@export var exit_angle_deg: float = 45.0
## ⚠️ PROJECT-DEFINED, deliberately lenient -- the owner: "只要摇晃的角速度超
## 过一定值（很宽松）并且身体是往前摆时，就能跳出去". Radians per second of
## FORWARD angular velocity.
@export var jump_min_omega: float = 0.8
## ⚠️ PROJECT-DEFINED. Angular acceleration W/S pumping adds when pushed WITH
## the current swing direction. The owner dials it.
@export var pump_accel: float = 3.0
## The magnet: how long the catch takes to pull the body onto the chain. Same
## number and same feel as the zipline's own fade.
@export var fade_in_time: float = 0.1
## Falling faster than this the hands cannot hold on (no CDO field for swing;
## borrowed from the zipline's confirmed one).
@export var fall_limit: float = 6.0
## ✅ SwingExitGravityModifier = 0.75 for SwingExitGravityModifierTime = 0.70 s
## (TdMove_SwingJump repeats nearly the same pair). Fed to
## Player.apply_gravity_window() on BOTH exits.
@export var exit_gravity_multiplier: float = 0.75
@export var exit_gravity_time: float = 0.7
## ⚠️ PROJECT-DEFINED: how long the bar just left refuses a re-catch.
@export var same_line_redo_time: float = 1.0

## ⚠️ OWNER-FELT (2026-08-25): "原地起跳上杆都能晃老高" -- the catch handed out
## up to 25 degrees of free amplitude (the magnet clamp) plus the full arrival
## momentum, and an undamped pendulum keeps whatever it is given forever.
## Three dials: the residual angle the magnet leaves, how much of the arrival
## momentum the hands absorb, and a light damping so an un-pumped swing
## settles -- ME makes you pump to KEEP swinging.
@export var entry_max_theta_deg: float = 8.0
@export var entry_omega_scale: float = 0.5
@export var damping: float = 0.4

## How much of the pendulum angle the MODEL leans by (about the bar). ✅ THE
## OWNER, on how ME sells amplitude: "主要是靠镜头里可以看到自己身体来判断" --
## the body tilts along the chain and the camera stays FREE (no forced pitch;
## ME does not sync the view to the swing).
@export var model_pitch_follow: float = 1.0
