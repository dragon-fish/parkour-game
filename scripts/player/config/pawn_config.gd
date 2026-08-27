class_name PawnConfig
extends Resource

# The Godot counterpart of the original's TdPawn CDO. Everything here is
# Pawn-wide -- shared by every move -- as opposed to MoveConfig, which is
# per-move. Field names follow the original's own (minus the Td prefix,
# snake_case); values are metric at 1 uu = 1 cm.

@export_group("Locomotion")
## [ME:CONFIRMED 02 §2.3] GroundSpeed = 720 uu/s.
## This is the CEILING of the speed-energy curve (02 §2.1), not a direct
## target speed. Read only by SpeedEnergy.cap() -- every move asks
## Player.speed_cap() instead of this field directly.
@export var ground_speed: float = 7.2
## [ME:CONFIRMED 02 §2.3] AirSpeed = 2400 uu/s. Essentially uncapped (3.3x
## GroundSpeed) -- the defence against an air-control exploit is air_control
## being almost zero, not a low ceiling here.
@export var air_speed: float = 24.0
## [ME:CONFIRMED 02 §2.3] AccelRate = 6144 uu/s^2 -> 61.44.
@export var accel_rate: float = 61.44
## [ME:CONFIRMED 02 §2.3] AirControl = 0.025. Engine default is 0.05; DICE
## halved it. Used as a multiplier on accel_rate (09 §9.1):
## air_accel = accel_rate * air_control = 61.44 * 0.025 = 1.536 m/s^2,
## derived inline in Player.air_accelerate() rather than stored as its own
## field -- see that function's own comment for why a full hang time can
## shed at most ~2.1 m/s even against continuous opposite input.
@export var air_control: float = 0.025
## [ME:CONFIRMED 02 §2.4] gravity is 16.0, MEASURED and not the configured
## value. `DefaultGravityZ` reads 800 uu/s^2 in DefaultGame.ini, but the
## effective gravity in game is twice that. 22 jumps read frame-by-frame off
## the debug HUD give apex 1.24 m and 0.775 s of airtime; those two numbers
## pin gravity and base_jump_z simultaneously, and only (16.0, 6.3) satisfies
## both. No scaling factor exists in any ini -- the doubling lives in native
## C++, like the speed-energy formula.
##
## Corroborated twice over: DICE's own comment above FallingUncontrolledHeight,
## that 1600 is the downward speed after falling 780 cm, resolves to within
## 1.3% under 1600 versus 30% off under 800; and SpringBoardJumpZ = 950
## predicts a 2.82 m springboard under 1600, which matches the owner's own
## measured "just over 2 m" where 800 would have predicted 5.64 m.
##
## Part of the gravity/base_jump_z/ground_speed trio: 09 §9.1 is explicit
## that retuning any one of the three alone makes the feel worse, not
## better, so they are calibrated as a group rather than independently. DO
## NOT put the ini's 800 back.
@export var gravity: float = 16.0
@export var terminal_velocity: float = 60.0
## [ME:CONFIRMED 02 §2.2] WalkVelocity = 50 uu/s -> 0.5 m/s as a VALUE.
## [ME:INFERRED] as a ROLE: the same section flags this discrete tier (and
## its four siblings) as more likely an animation-blend threshold than a true
## speed clamp, since the real ground ceiling is the speed curve
## (GroundSpeed) -- so the role recorded here, a hard cap on speed while the
## walk modifier / Ctrl is held, is unverified. Used anyway, per the owner's
## own direction that Ctrl should move the player very slowly -- 0.5 m/s (7%
## of ground_speed) reads as exactly that, not as an implausible number, so
## there was no reason to substitute a different one.
@export var walk_velocity: float = 0.5
## [ME:CONFIRMED 02 §2.3] CrouchedPct = 0.4. Also lives as CrouchConfig's own
## speed_modifier; kept here too because the original declares it Pawn-wide.
@export var crouched_pct: float = 0.4
## [ME:CONFIRMED 02 §2.3] MaxStepHeight = 35 uu. Read by Player.try_step_up().
##
## Godot's move_and_slide() does not provide step-up on its own --
## floor_snap_length only keeps a body attached on the way DOWN -- so this is
## read explicitly. Skipping that read left ankle-high clutter (a 5 cm plank)
## stopping a run dead.
@export var max_step_height: float = 0.35
## PROJECT-ADDED, no counterpart in the original -- it exists because
## try_step_up() is this project's own answer to Godot having no built-in
## step-up. The probe raises the body IN PLACE and leaves move_and_slide() to
## carry it forward onto the step, which takes a tick or two during which the
## body is genuinely airborne. Without a window, every move that treats
## "left the floor" as "walked off a ledge" cancels itself on a kerb it rode
## over successfully -- measured as Slide -> Falling -> Grab -> Falling ->
## Walking against a 0.30 m one.
##
## 0.1 s is about six ticks, comfortably more than the two the manoeuvre
## takes, and short enough that a genuine ledge exit within the window falls
## about 8 cm before Falling takes over -- below the threshold of noticing.
@export var step_up_grace_time: float = 0.1
## [ME:CONFIRMED 02 §2.3] WalkableFloorZ = 0.71 -> acos = 44.7 degrees. This
## also lands within a third of a degree of Godot's own floor_max_angle
## default (45 degrees), so the probe gates and CharacterBody3D's own floor
## test agree about what a floor is.
@export var walkable_floor_z: float = 0.71

@export_group("Jump")
## [ME:CONFIRMED 02 §2.4] measured base_jump_z = 630 uu/s (TdMove_Jump.BaseJumpZ,
## 6.3 m/s here), from the same 22-jump frame data as gravity above (apex
## 1.24 m, airtime 0.775 s) -- no other pairing with gravity 16.0 satisfies
## both. TdPawn also declares BaseJumpZ = 560; that number only ever bounded
## the value from above via an inequality and is NOT a competing
## measurement -- do not read it as one.
##
## Calibrated together with gravity and the landing thresholds below, not
## independently -- 09 §9.1 is explicit that retuning any one of
## jump/gravity/landing alone makes the feel worse, not better. At this
## apex (1.24 m) an ordinary flat jump's fall distance stays 0.76 m under
## skill_roll_landing_height (2.0 m), so it never rises above TIER_FREE --
## see Player.landing_tier() and landing_keep_ratio().
@export var base_jump_z: float = 6.3
## [ME:CONFIRMED 02 §2.4] JumpAddXY = 100 uu/s as a VALUE. [ME:INFERRED] as a
## ROLE: read as an ADDITION along the facing at take-off rather than a
## minimum, since taking off is itself a small forward commitment -- whether
## the original adds or floors is not verified. Wired into WalkingMove's and
## SlideMove's jump branches via Player.jump_add_velocity().
@export var jump_add_xy: float = 1.0
## No confirmed counterpart in the original (02 §2.4 searched and found
## none). Kept as a modern quality-of-life affordance.
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

@export_group("Friction")
## No confirmed value in the original -- the research did not extract
## TdPawn.Friction. Every scale below is relative to this field, so it is the
## one number in this group that has to be settled by playtest.
@export var base_friction: float = 40.0
## [ME:CONFIRMED 03 §3.3] terrain grade modulates friction directly: downhill
## is a free acceleration lane, uphill is a tax.
@export var upward_walk_friction_scale: float = 1.1
@export var downward_walk_friction_scale: float = 0.8
@export var min_walk_friction_modify: float = 0.4
@export var max_walk_friction_modify: float = 2.0
## [ME:CONFIRMED 03 §3.3] a slide's grade sensitivity is far more extreme
## than walking's -- uphill sliding stops almost immediately.
@export var upward_slide_friction_scale: float = 5.0
@export var downward_slide_friction_scale: float = 1.8
## [ME:CONFIRMED 03 §3.3] TdPawn declares 1.0; TdPlayerPawn overrides to 0.5 --
## the player is deliberately harder to bring to a stop than the AI.
@export var braking_friction_strength: float = 0.5
## Godot-specific: the downward bias every grounded move writes each tick so
## is_on_floor() does not flicker across seams. The original's PHYS_Walking
## has no equivalent because it does not need one.
@export var floor_snap_speed: float = 2.0

@export_group("Speed energy")
## [ME:CONFIRMED 02 §2.1] LINEAR reproduces the original exactly: its
## InterpCurveFloat carries an interpolation mode alongside its knots, and
## CIM_Linear is the value actually set on SpeedCurve_LightWeapon.
## SMOOTH (see speed_curve_smooth_fit) is a project-added opt-in feel
## variant, not from the original: since accel_rate is far larger than any
## segment's slope, the curve's slope IS the felt acceleration, so the
## piecewise LINEAR form steps it 10.0 -> 2.0 -> 0.52 -> 0.20 m/s^2 at three
## instants. Whether that reads as a gear change is an empirical question, so
## it is a switch, not an argument -- 0 = LINEAR, 1 = SMOOTH.
@export_enum("LINEAR", "SMOOTH") var speed_curve_interp_mode: int = 0
## (A, a, B, b) of v(E) = A*(1 - e^(-E/a)) + B*(1 - e^(-E/b)), the SMOOTH
## mode's curve. Project-added, not from the original -- no evidence tag
## applies to a value with no source uu. Fitted OFFLINE to the five confirmed
## knots above with scipy.optimize.curve_fit; measured residual at every knot
## is under 1e-4, i.e. this passes through all five confirmed points and only
## differs BETWEEN them -- exactly the region the source data never
## constrained. Peak divergence from LINEAR is +0.76 m/s at E = 0.17 (the
## opening 0.4 s is noticeably punchier); the sum A + B = 7.556 overshoots
## ground_speed, so SpeedEnergy.cap() clamps.
##
## IF THE KNOTS ABOVE ARE EVER EDITED, THESE MUST BE REFITTED:
##   import numpy as np; from scipy.optimize import curve_fit
##   t = np.array([0,.4,1,3.5,7.]); v = np.array([0,4.,5.2,6.5,7.2])
##   f = lambda t,A,a,B,b: A*(1-np.exp(-t/a)) + B*(1-np.exp(-t/b))
##   print(curve_fit(f, t, v, p0=[4,.3,3,3.], maxfev=200000)[0])
## tests/test_speed_energy.gd's knot test is the guard against forgetting.
@export var speed_curve_smooth_fit: Vector4 = Vector4(4.4222, 0.23199, 3.1335, 3.2169)
## [ME:CONFIRMED 02 §2.1] SpeedCurve_LightWeapon, an InterpCurveFloat with
## interpolation mode CIM_Linear. X is speed energy in seconds, Y is the
## ground speed ceiling. Held as the five confirmed knots rather than a
## fitted formula: the original evaluates a table, so a table has zero
## approximation error where a formula does not.
@export var speed_curve: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(0.4, 4.0), Vector2(1.0, 5.2),
	Vector2(3.5, 6.5), Vector2(7.0, 7.2),
])
## [ME:CONFIRMED 02 §2.1] SpeedMinBaseVelocity = 10 uu/s. Floor under the
## curve so a standing start is not literally frozen at the curve's own
## v(0) = 0.
@export var speed_min_base_velocity: float = 0.1
## [ME:CONFIRMED 02 §2.1] SpeedMaxBaseVelocity = 400 uu/s as a VALUE.
##
## [ME:INFERRED] as a ROLE: the floor below which turning stops costing
## speed. The owner played the original and reports that however hard the
## view is swung, speed never falls below roughly 16 km/h (4.44 m/s) -- and
## this field, the one number in the whole speed block with no known
## consumer, sits at 4.0 m/s. Close enough that giving it this job explains
## both the observation and the field's existence.
##
## Read by SpeedEnergy.spend_turn(), via energy_for_speed().
@export var speed_max_base_velocity: float = 4.0
## [ME:CONFIRMED 02 §2.1] the three factors below as VALUES. [ME:INFERRED] as
## a FORMULA: energy accrues at (active factor / sprint factor) per second,
## so ordinary running is 30/30 = 1.0 and the curve's 7.0 s X-axis endpoint is
## reached in exactly 7 s -- not verified against bytecode.
## [ME:COMMUNITY] independently reports 7-10 seconds from a standstill to
## full sprint, which corroborates the reading above.
@export var speed_walk_velocity_acceleration_factor: float = 7.0
@export var speed_strafe_velocity_acceleration_factor: float = 10.0
@export var speed_sprint_velocity_acceleration_factor: float = 30.0
## [ME:CONFIRMED 02 §2.1] SpeedEnergyDecelerationTime = 3.
@export var speed_energy_deceleration_time: float = 3.0
## [ME:CONFIRMED 02 §2.1] SpeedEnergyDecelerationExponent = 0.5 as a VALUE.
## [ME:INFERRED] as a FORMULA: taken literally as the exponent in
## dE/dt = -k * E^0.5, with k solved from speed_energy_deceleration_time
## above.
@export var speed_energy_deceleration_exponent: float = 0.5
## [ME:UNKNOWN 03 §3.2] SpeedTurnDecelerationFactor = 10 in the original, but
## its UNIT is not recoverable from the binary. DO NOT use that number
## directly. Instead this project calibrates the knob to a stated behaviour:
## a full 180 degree reversal (pi radians) spends the entire 7.0 energy
## budget, so cost per radian = energy ceiling / PI = 7.0 / pi = 2.2282 --
## exact, rather than the earlier 2.23 rounding.
@export var turn_rate_cost_curve: PackedVector2Array = PackedVector2Array([
	Vector2(95.0, 0.239),
	Vector2(225.0, 0.585),
	Vector2(450.0, 1.0),
	Vector2(1050.0, 1.327),
])
@export var speed_turn_deceleration_factor: float = 2.2282
## PROJECT-ADDED GUARD, no counterpart in the original. Energy only accrues
## while actually travelling at this fraction of the current cap. DO NOT
## remove or zero this: holding the walk modifier for 7 seconds -- or
## shoving into a wall for 7 seconds -- would bank a full energy budget and
## hand over a 7.2 ceiling the instant the obstruction clears, contradicting
## the premise that speed is an asset that has to be run for.
@export var energy_accumulate_speed_ratio: float = 0.9

@export_group("Landing")
## [ME:CONFIRMED 03 §3.1] TdMove_Landing CDO, as fall HEIGHTS (not impact
## speeds): 200 / 300 / 530 uu.
@export var skill_roll_landing_height: float = 2.0
@export var soft_landing_height: float = 3.0
@export var hard_landing_height: float = 5.3
## [ME:CONFIRMED 03 §3.1] TdMove_Falling.EnterToFallingZSpeed = -200 uu/s.
##
## The boundary between the two airborne states that own a descent: Jump
## hands off to Falling on the first tick velocity.y drops to or below this
## (see JumpMove.physics_update()). Jump carries check_for_wall_climb and
## Falling does not, so this is the speed at which a launch stops being one
## and a wall stops being reachable; and only Falling may hand off to
## FallingUncontrolled, so it is also where a descent first becomes able to
## turn fatal (invariant I2).
##
## DO NOT read this as a fall-counter arming threshold: FallTracker measures
## from where the feet LEFT THE GROUND and arms on nothing at all -- see its
## own header for the measurement that rules the armed-then-track-the-apex
## model out.
##
## [ME:CONFIRMED 03 §3.1] landing speed loss is BINARY, not a ratio -- all
## three readings of the original's LandingSpeedReduction = 65 are excluded
## by measurement: a 4.95 m unrolled drop costs nothing (ruling out "subtract
## 65 uu/s"), and a hard landing costs everything (ruling out both "lose 65%"
## and "keep 65%"). DO NOT add a landing-speed-reduction ratio knob -- the
## real behaviour needs no ratio, and the original's own meaning for that
## field is [ME:UNKNOWN].
@export var enter_to_falling_z_speed: float = -2.0
## [ME:CONFIRMED 03 §3.1] TdPawn.RollTriggerTime = 1.0 as a VALUE.
## [ME:INFERRED] as a ROLE: read as the roll input pre-buffer window.
## [ME:COMMUNITY] extremely forgiving next to the 0.1-0.2 s typical of the
## genre, matching the community's own "skill roll timing is very lenient"
## consensus.
@export var roll_trigger_time: float = 1.0
## [ME:CONFIRMED 03 §3.1] TdMove_Falling.MaximumSpeedForRollLanding = -5000.
@export var maximum_speed_for_roll_landing: float = -50.0

@export_group("World")
## [ME:CONFIRMED 02/03] TdPawn.FallingUncontrolledHeight = 1000 uu -> 10.0 m.
## Measured in the original: crossing this depth takes control away outright
## (TdMove_FallingUncontrolled's ControllerState is PlayerDying) -- it is NOT
## a damage calculation performed on impact, and no roll can save it.
##
## Checked DURING the descent (see FallingMove), not looked up at touchdown:
## the difference is whether the player spends the last second of the fall
## still believing they can act.
@export var falling_uncontrolled_height: float = 10.0
## How far below y = 0 the player must fall before Arena teleports them back.
## Project-specific; the original has no equivalent.
@export var fall_recovery_depth: float = 20.0
## Horizontal speed above which CharacterAnimator plays a moving clip. A
## readability threshold, not a physics one.
@export var run_animation_speed_threshold: float = 1.0


## How fast the visible body turns to face where it is going, in degrees per
## second. Only the MODEL: the body's real facing follows the view instantly,
## as it always has, and every probe and move still reads that.
##
## The owner's complaint is what this is for: standing still and turning the
## camera swung the whole character round, which reads as the model being
## welded to the mouse rather than as a person looking about. Now the model
## HOLDS its heading while there is no movement input, and catches up over this
## rate once there is.
@export var body_turn_speed_deg: float = 540.0

## Below this much movement input the model holds its heading rather than
## following the view. A dead zone rather than an exact zero, so a stick barely
## off centre does not count as a decision to turn.
@export var body_turn_input_threshold: float = 0.2
