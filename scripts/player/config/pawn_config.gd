class_name PawnConfig
extends Resource

# The Godot counterpart of the original's TdPawn CDO. Everything here is
# Pawn-wide -- shared by every move -- as opposed to MoveConfig, which is
# per-move. Field names follow the original's own (minus the Td prefix,
# snake_case); values are metric at 1 uu = 1 cm.

@export_group("Locomotion")
## Source: 02 §2.3 `GroundSpeed = 720` uu/s. ✅
## From Task 6 this stops being the target speed directly and becomes the
## CEILING of the speed-energy curve (02 §2.1); it keeps the same value.
@export var ground_speed: float = 7.2
## Source: 02 §2.3 `AirSpeed = 2400` uu/s. ✅ Essentially uncapped (3.3x
## GroundSpeed) -- the defence against an air-control exploit is air_control
## being almost zero, not a low ceiling here.
@export var air_speed: float = 24.0
## Source: 02 §2.3 `AccelRate = 6144` uu/s^2 -> 61.44. ✅
## MIGRATION NOTE: carried over from the old `ground_accel = 60.0`, NOT yet
## re-pointed at the confirmed 61.44 -- this task changes no values. Task 6
## corrects it.
@export var accel_rate: float = 60.0
## Source: 02 §2.3 `AirControl = 0.025`. ✅ Engine default is 0.05; DICE
## halved it. Used as a multiplier on accel_rate (09 §9.1).
## MIGRATION NOTE: the old flat `air_accel = 1.5` is carried in air_accel
## below until Task 6 derives it from this instead.
@export var air_control: float = 0.025
## Source: 09 §9.1 / 02 §2.3 -- ME's `AirControl = 0.025` is not an
## acceleration in its own right; the guide reads it as a MULTIPLIER on
## ground accel ("AirControl 0.025 × 加速度"). Applied to this project's own
## accel_rate (60.0, itself already ~= ME's AccelRate 61.44, see accel_rate's
## own comment) rather than to ME's raw AccelRate, since this is the number
## Player.air_accelerate() actually gets compared against:
##   air_accel = accel_rate * 0.025 = 60.0 * 0.025 = 1.5
## Deliberately not a speed-ceiling fix (see air_speed's own comment for why
## the old air_max_speed = 9.0 was the wrong lever entirely) -- with the
## post-retune 1.58 s hangtime (gravity 24.0 -> 8.0, see gravity's own
## comment), the old air_accel (12.0) could ratchet horizontal speed past
## ground_speed over repeated jumps; at 1.5, a full hangtime of continuous
## same-direction air control adds at most air_accel * 1.58 =~ 2.4 m/s, and
## landing's own speed cost removes far more than that on any landing hard
## enough to matter -- was pinned by tests/legacy/test_air_state.gd's
## test_air_strafing_across_chained_jumps_never_exceeds_the_ground_speed_cap
## -- ARCHIVED by Task 1 and NOT in the running suite, so nothing enforces
## this today; restore the pin when the behavioural suite is rewritten.
## MIGRATION NOTE: this is the stored value carried from before air_control
## existed. Task 7 deletes this field and derives air_accel inline instead,
## as `config.pawn.accel_rate * config.pawn.air_control`.
@export var air_accel: float = 1.5
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
## there.
## MIGRATION NOTE: still carrying the old 6.3 (which came from the ruled-out
## 630). Task 6 corrects it to 5.6, together with the landing thresholds --
## 09 §9.1 is explicit that these must be calibrated as a group.
@export var base_jump_z: float = 6.3
## Source: 02 §2.4 `JumpAddXY = 100` uu/s. ⚠️ Inferred as extra horizontal
## speed along the facing at the moment of take-off; whether it adds or sets
## a minimum is unverified. Wired up in Task 6.
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
## the entire 7.0 energy budget, hence 7.0 / pi = 2.23 energy per radian.
@export var speed_turn_deceleration_factor: float = 2.23
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
## Deleted by Task 9 (fall-height landing tiers).
@export var land_cost_speed_ref: float = 9.21
@export var land_speed_keep: float = 0.55
@export var roll_speed_keep: float = 0.94
@export var roll_min_fall_speed: float = 5.0
## Deleted by Task 9 (single roll_trigger_time buffer).
@export var crouch_buffer_time: float = 0.15
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
