class_name PawnConfig
extends Resource

# The Godot counterpart of the original's TdPawn CDO. Everything here is
# Pawn-wide -- shared by every move -- as opposed to MoveConfig, which is
# per-move. Field names follow the original's own (minus the Td prefix,
# snake_case); values are metric at 1 uu = 1 cm.

@export_group("Locomotion")
## Source: 02 §2.3 `GroundSpeed = 720` uu/s. ✅
## From Task 7 this stops being the target speed directly and becomes the
## CEILING of the speed-energy curve (02 §2.1); it keeps the same value.
## Read only by SpeedEnergy.cap() -- every move asks Player.speed_cap()
## instead of this field directly.
@export var ground_speed: float = 7.2
## Source: 02 §2.3 `AirSpeed = 2400` uu/s. ✅ Essentially uncapped (3.3x
## GroundSpeed) -- the defence against an air-control exploit is air_control
## being almost zero, not a low ceiling here.
@export var air_speed: float = 24.0
## Source: 02 §2.3 `AccelRate = 6144` uu/s^2 -> 61.44. ✅
@export var accel_rate: float = 61.44
## Source: 02 §2.3 `AirControl = 0.025`. ✅ Engine default is 0.05; DICE
## halved it. Used as a multiplier on accel_rate (09 §9.1):
## air_accel = accel_rate * air_control = 61.44 * 0.025 = 1.536 m/s^2,
## derived inline in Player.air_accelerate() rather than stored as its own
## field -- see that function's own comment for why a full hang time can
## shed at most ~2.1 m/s even against continuous opposite input.
@export var air_control: float = 0.025
## Source: 09 §9.1 `DefaultGravityZ = 800` uu/s^2. ✅
## Part of the gravity/base_jump_z/ground_speed trio: the guide is explicit
## that retuning any one of the three alone makes the feel worse, not
## better, so they are calibrated as a group rather than independently.
@export var gravity: float = 8.0
@export var terminal_velocity: float = 60.0
## Source: 02 §2.2 `WalkVelocity = 50` uu/s -> 0.5 m/s. ✅ as a VALUE. The same
## section flags this discrete tier (and its four siblings) as MORE LIKELY an
## animation-blend threshold than a true speed clamp ("这五个值更可能是动画混合
## 的阈值...而非速度钳制值"), since the real ground ceiling is the speed curve
## (GroundSpeed) -- so the ROLE recorded here (a hard cap on speed while the
## walk modifier / Ctrl is held) is ⚠️ inferred, not confirmed. Used anyway,
## per the owner's own direction that Ctrl should move the player "very
## slowly" -- 0.5 m/s (7% of ground_speed) reads as exactly that, not as an
## implausible number, so there was no reason to substitute a different one.
@export var walk_velocity: float = 0.5
## Source: 02 §2.3 `CrouchedPct = 0.4`. ✅ Also lives as CrouchConfig's own
## speed_modifier; kept here too because the original declares it Pawn-wide.
@export var crouched_pct: float = 0.4
## Source: 02 §2.3 `MaxStepHeight = 35` uu. ✅ Read by Player.try_step_up().
##
## An earlier note here said Godot's move_and_slide() had its own step handling
## so nothing needed to read this. It does not -- floor_snap_length only keeps a
## body attached on the way DOWN -- and that assumption is why ankle-high
## clutter (a 5 cm plank) stopped a run dead.
@export var max_step_height: float = 0.35
## Source: 02 §2.3 `WalkableFloorZ = 0.71` -> acos = 44.7 degrees. ✅
## Carried over from the old `min_walkable_normal_y = 0.7`; Task 14 moves it
## to the confirmed 0.71.
@export var walkable_floor_z: float = 0.7

@export_group("Jump")
## Source: 02 §2.4 `TdPawn.BaseJumpZ = 560` uu/s. ✅ CONFIRMED BY IN-GAME
## MEASUREMENT -- the conflicting `TdMove_Jump.BaseJumpZ = 630` is ruled out
## there. Against gravity 8.0 this peaks at 1.96 m, four centimetres under
## the 2.0 m skill_roll_landing_height, which is what keeps an ordinary flat
## jump free of the landing penalty -- see landing_keep_ratio()'s own comment.
## Calibrated together with the landing thresholds below, not independently --
## 09 §9.1 is explicit that retuning any one of jump/gravity/landing alone
## makes the feel worse, not better.
@export var base_jump_z: float = 5.6
## Source: 02 §2.4 `JumpAddXY = 100` uu/s. ⚠️ Inferred as an ADDITION along
## the facing at take-off (whether it adds or sets a minimum is unverified);
## taking off is itself a small forward commitment. Wired in WalkingMove and
## SlideMove's jump branches.
@export var jump_add_xy: float = 1.0
## No confirmed counterpart in the original (02 §2.4 searched and found
## none). Kept as a modern quality-of-life affordance.
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

@export_group("Friction")
## No confirmed value in the original -- the research did not extract
## TdPawn.Friction. Carried over from this project's own ground_friction, and
## every scale below is relative to it, so this is the one number in this
## group that has to be settled by playtest.
@export var base_friction: float = 40.0
## Source: 03 §3.3. ✅ Terrain grade modulates friction directly: downhill is
## a free acceleration lane, uphill is a tax.
@export var upward_walk_friction_scale: float = 1.1
@export var downward_walk_friction_scale: float = 0.8
@export var min_walk_friction_modify: float = 0.4
@export var max_walk_friction_modify: float = 2.0
## Source: 03 §3.3. ✅ A slide's grade sensitivity is far more extreme than
## walking's -- uphill sliding stops almost immediately.
@export var upward_slide_friction_scale: float = 5.0
@export var downward_slide_friction_scale: float = 1.8
## Source: 03 §3.3. ✅ TdPawn declares 1.0; TdPlayerPawn overrides to 0.5 --
## the player is deliberately harder to bring to a stop than the AI.
@export var braking_friction_strength: float = 0.5
## Godot-specific: the downward bias GroundState writes every tick so
## is_on_floor() does not flicker across seams. The original's PHYS_Walking
## has no equivalent because it does not need one.
@export var floor_snap_speed: float = 2.0

@export_group("Speed energy")
## Source: 02 §2.1 -- the original's InterpCurveFloat carries an
## interpolation mode alongside its knots; CIM_Linear is the value actually
## set on SpeedCurve_LightWeapon. ✅ LINEAR reproduces that exactly. SMOOTH
## (see speed_curve_smooth_fit) is a project-added opt-in feel variant: since
## accel_rate is far larger than any segment's slope, the curve's slope IS
## the felt acceleration, so the piecewise LINEAR form steps it
## 10.0 -> 2.0 -> 0.52 -> 0.20 m/s^2 at three instants. Whether that reads as
## a gear change is an empirical question, so it is a switch, not an
## argument -- 0 = LINEAR, 1 = SMOOTH.
@export_enum("LINEAR", "SMOOTH") var speed_curve_interp_mode: int = 0
## (A, a, B, b) of v(E) = A*(1 - e^(-E/a)) + B*(1 - e^(-E/b)), the SMOOTH
## mode's curve. Project-added, not from the original -- no ✅/⚠️/❓ marker
## applies to a value that has no source uu. Fitted OFFLINE to the five
## confirmed knots above with scipy.optimize.curve_fit; measured residual at
## every knot is under 1e-4, i.e. this passes through all five confirmed
## points and only differs BETWEEN them -- exactly the region the source data
## never constrained. Peak divergence from LINEAR is +0.76 m/s at E = 0.17
## (the opening 0.4 s is noticeably punchier); the sum A + B = 7.556
## overshoots ground_speed, so SpeedEnergy.cap() clamps.
##
## IF THE KNOTS ABOVE ARE EVER EDITED, THESE MUST BE REFITTED:
##   import numpy as np; from scipy.optimize import curve_fit
##   t = np.array([0,.4,1,3.5,7.]); v = np.array([0,4.,5.2,6.5,7.2])
##   f = lambda t,A,a,B,b: A*(1-np.exp(-t/a)) + B*(1-np.exp(-t/b))
##   print(curve_fit(f, t, v, p0=[4,.3,3,3.], maxfev=200000)[0])
## tests/test_speed_energy.gd's knot test is the guard against forgetting.
@export var speed_curve_smooth_fit: Vector4 = Vector4(4.4222, 0.23199, 3.1335, 3.2169)
## Source: 02 §2.1 `SpeedCurve_LightWeapon`, an InterpCurveFloat with
## interpolation mode CIM_Linear. ✅ X is speed energy in seconds, Y is the
## ground speed ceiling. Held as the five confirmed knots rather than a
## fitted formula: the original evaluates a table, so a table has zero
## approximation error where a formula does not.
@export var speed_curve: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.4, 4.0), Vector2(1.0, 5.2),
	Vector2(3.5, 6.5), Vector2(7.0, 7.2),
])
## Source: 02 §2.1 `SpeedMinBaseVelocity = 10` uu/s. ✅ Floor under the curve
## so a standing start is not literally frozen at the curve's own v(0) = 0.
@export var speed_min_base_velocity: float = 0.1
## Source: 02 §2.1 `SpeedMaxBaseVelocity = 400` uu/s. ✅ as a value,
## ❓ as a role -- the research could not determine what it does in the
## formula. Recorded so the number is not lost; nothing reads it.
@export var speed_max_base_velocity: float = 4.0
## Source: 02 §2.1. ✅ as values, ⚠️ as direction (unverified by bytecode).
## Read as: energy accrues at (active factor / sprint factor) per second, so
## ordinary running is 30/30 = 1.0 and the curve's 7.0 s X-axis endpoint is
## reached in exactly 7 s -- which is what the community's own "7-10 seconds
## from a standstill to full sprint" measurement independently reports.
@export var speed_walk_velocity_acceleration_factor: float = 7.0
@export var speed_strafe_velocity_acceleration_factor: float = 10.0
@export var speed_sprint_velocity_acceleration_factor: float = 30.0
## Source: 02 §2.1 `SpeedEnergyDecelerationTime = 3`. ✅
@export var speed_energy_deceleration_time: float = 3.0
## Source: 02 §2.1 `SpeedEnergyDecelerationExponent = 0.5`. ✅ as a value,
## ⚠️ as a formula -- taken literally as the exponent in
## dE/dt = -k * E^0.5, with k solved from the time above.
@export var speed_energy_deceleration_exponent: float = 0.5
## Source: 03 §3.2 `SpeedTurnDecelerationFactor = 10`. ❓ THE UNIT IS NOT
## RECOVERABLE from the binary. The original value is recorded here in the
## comment and deliberately NOT used: this project calibrates the knob to a
## stated behaviour instead -- a full 180 degree reversal (pi radians) spends
## the entire 7.0 energy budget, hence energy ceiling / PI = 7.0 / pi =
## 2.2282 energy per radian, exact rather than the earlier 2.23 rounding.
@export var speed_turn_deceleration_factor: float = 2.2282
## PROJECT-ADDED GUARD, no counterpart in the original. Energy only accrues
## while actually travelling at this fraction of the current cap. Without it,
## holding the walk modifier for 7 seconds -- or shoving into a wall for 7
## seconds -- banks a full energy budget and hands over a 7.2 ceiling the
## instant the obstruction clears, which contradicts the whole premise that
## speed is an asset that has to be run for.
@export var energy_accumulate_speed_ratio: float = 0.9

@export_group("Landing")
## Source: 03 §3.1 `TdMove_Landing` CDO, as fall HEIGHTS (not impact
## speeds). ✅ 200 / 300 / 530 uu.
@export var skill_roll_landing_height: float = 2.0
@export var soft_landing_height: float = 3.0
@export var hard_landing_height: float = 5.3
## Source: 03 §3.1 `LandingSpeedReduction = 65`. ❓ UNIT UNVERIFIED -- the
## research calls this its single most important open question. Read as
## "lose 65%", i.e. keep 0.35, on the strength of the community consensus
## that a hard landing takes speed almost to zero.
@export var landing_speed_reduction: float = 0.65
## Source: 03 §3.1 `TdMove_Falling.EnterToFallingZSpeed = -200` uu/s. ✅
## The downward speed at which the fall-height counter starts accruing, so
## the first few centimetres of a step-off are not counted.
@export var enter_to_falling_z_speed: float = -2.0
## Source: 03 §3.1 `TdPawn.RollTriggerTime = 1.0`. ⚠️ Read as the roll input
## pre-buffer window. Extremely forgiving next to the 0.1-0.2 s typical of
## the genre, which matches the community's own "skill roll timing is very
## lenient" consensus.
@export var roll_trigger_time: float = 1.0
## Source: 03 §3.1 `TdMove_Falling.MaximumSpeedForRollLanding = -5000`. ✅
@export var maximum_speed_for_roll_landing: float = -50.0

@export_group("Legacy -- deleted by later tasks")
## MIGRATION ONLY. Every field below is a project invention with no
## counterpart in the original, carried unchanged so this task can be shown
## to change no behaviour. Each is deleted by the task that lands its
## replacement -- see the spec's own deletion table (§6).
## Deleted by Task 11/12 (redo_move_time).
@export var wall_reattach_cooldown: float = 0.5
@export var wall_same_normal_dot: float = 0.85
## Deleted by Task 13 (redo_move_time).
@export var ledge_regrab_cooldown: float = 0.45

@export_group("World")
## How far below y = 0 the player must fall before Arena teleports them back.
## Project-specific; the original has no equivalent.
@export var fall_recovery_depth: float = 20.0
## Horizontal speed above which CharacterAnimator plays a moving clip. A
## readability threshold, not a physics one.
@export var run_animation_speed_threshold: float = 1.0
