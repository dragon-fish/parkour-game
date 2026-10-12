class_name PawnConfig
extends Resource

# The Godot counterpart of the original's TdPawn CDO. Everything here is
# Pawn-wide -- shared by every move -- as opposed to MoveConfig, which is
# per-move. Field names follow the original's own (minus the Td prefix,
# snake_case); values are metric at 1 uu = 1 cm.

@export_group("Locomotion")
## [ME:CONFIRMED 02 §2.3] GroundSpeed = 720 uu/s.
## This is the CEILING of the speed curve (02 §2.1), not a direct target
## speed: the ported acceleration reads it (PawnAcceleration.Params).
@export var ground_speed: float = 7.2
## [ME:CONFIRMED 02 §2.3] AirSpeed = 2400 uu/s. Essentially uncapped (3.3x
## GroundSpeed) -- the defence against an air-control exploit is air_control
## being almost zero, not a low ceiling here.
@export var air_speed: float = 24.0
## [ME:CONFIRMED 02 §2.3] AccelRate = 6144 uu/s^2 -> 61.44.
@export var accel_rate: float = 61.44

## Top speed when NOT travelling roughly forwards, in m/s.
##
## Sideways running settles at speed_max_base_velocity, and that is not a
## coincidence to be tidied away later.
##
## [ME:CONFIRMED] Read off a 120 fps capture through hud_ocr.py, view held
## still so heading comes from differencing the HUD's X/Y:
##
##   t=18.87  25.9 km/h   heading  -0.2 deg   running straight
##   t=18.93  20.6 km/h   heading  63.2 deg   the dip, as the turn is billed
##   t=19.03  22.6 km/h   heading  86.9 deg   already fully sideways
##   t=19.28  24.8 km/h   heading  89.8 deg   STILL CLIMBING, sideways
##   t=19.90  22.2 km/h   heading  89.8 deg   the ceiling starts down
##   t=21.93  14.5 km/h   heading  89.8 deg   settled at base speed
##
## THE CLIMB AT 89.8 DEGREES IS WHY THERE IS NO SIDEWAYS CAP. A body running
## dead sideways accelerated to 24.8 km/h, which no ceiling of 14.4 permits.
## Nothing limits the speed; the CEILING slides down, over about 2.6 s
## against speed_energy_deceleration_time's 3.0, and stops where every other
## drain stops -- at the energy that buys speed_max_base_velocity, 4.0 m/s,
## which is 14.4 km/h. In the port that is GetWalkAcceleration's decay of
## SpeedSprintEnergy while the input points across the facing.
##
## DO NOT declare a lateral_speed of 4.0 and clamp the speed to it: it gives
## the right endpoint and the wrong curve, and 14.4 is a number the model
## already has.

## Half-angle of the arc, in degrees, inside which the full ground speed is
## available. 45 makes the arc 90 degrees wide: straight ahead and both
## diagonals run at full speed, straight sideways does not.
##
## [ME:CONFIRMED] Owner: "前方90°内才能到满速".
@export var forward_arc_deg: float = 45.0

## [ME:CONFIRMED 02 §2.3] AirControl = 0.025. Engine default is 0.05; DICE
## halved it. [ME:CONFIRMED emulated N2 §2] the falling acceleration bound is
## accel_rate * air_control = 1.536 m/s^2, which the falling integrator doubles;
## at ground_speed and above it is 0.01 m/s^2 (PawnPhysics.falling_accel_bound).
@export var air_control: float = 0.025
## The world's gravity as the original configures it: DefaultGravityZ = -800
## uu/s^2. [ME:CONFIRMED emulated N2 §1] TdPawn::GetGravityZ returns this
## times GravityModifier and nothing else -- no hidden factor. What a falling
## body FEELS is twice it, because physFalling integrates
## V1 = V0 + a dt, moves by V1 dt and rebuilds V = 2 dLoc / dt - V0: a
## parabola with acceleration 2a, independent of the step. PawnPhysics
## integrates exactly that; DO NOT double this number.
@export var world_gravity_z: float = -8.0
## The gravity a falling body feels, 2 x |world_gravity_z|, for the moves not
## yet ported, which integrate their own falls. [ME:CONFIRMED 02 §2.4]
## measured (apex 1.24 m, airtime ~0.78 s from BaseJumpZ 630) and
## [ME:DERIVED] from the integrator above.
@export var gravity: float = 16.0
## PhysicsVolume.TerminalVelocity: [ME:CONFIRMED emulated N2 §2] the CDO's
## 3500 uu/s, clamping the whole velocity after the falling rebuild.
@export var terminal_velocity: float = 35.0
## [ME:CONFIRMED 02 §2.2] WalkVelocity = 50 uu/s -> 0.5 m/s as a VALUE.
## [ME:INFERRED] as a ROLE: the same section flags this discrete tier (and
## its four siblings) as more likely an animation-blend threshold than a true
## speed clamp. Read only by CharacterAnimator, as the slowest a walk clip is
## scaled down to; the walk key scales the input by walk_button_multiplier.
@export var walk_velocity: float = 0.5
## TdPlayerInput.WalkButtonMultiplier: [ME:CONFIRMED decompile] the walk key
## scales aForward and aStrafe by this, after InputSize is taken -- so a walk
## never asks for a sprint (aForward 0.3 < 0.7).
@export var walk_button_multiplier: float = 0.3
## [ME:CONFIRMED 02 §2.3] CrouchedPct = 0.4. Also lives as CrouchConfig's own
## speed_modifier; kept here too because the original declares it Pawn-wide.
@export var crouched_pct: float = 0.4
## The tallest rise the body walks straight up without a vault, metres. Read by
## Player.try_step_up(), and by Probes.vault_query() as the floor under which
## nothing is vaulted.
##
## [ME:CONFIRMED] measured in the original at 0.4 m. [ME:DERIVED] that is the
## walking physics' own step, not a second constant: it climbs
## MaxStepHeight + 2 uu (max_step_down_height + 0.02) from a body that hovers
## 2.15 uu above its floor, about 0.39 m. The ported walking physics does not
## read this field.
##
## Godot's move_and_slide() does not provide step-up on its own --
## floor_snap_length only keeps a body attached on the way DOWN -- so this is
## read explicitly. Skipping that read left ankle-high clutter (a 5 cm plank)
## stopping a run dead.
@export var max_step_height: float = 0.4
## [ME:CONFIRMED 02 §2.3] Pawn.MaxStepHeight = 35 uu. The walking physics
## (PawnPhysics) reaches MaxStepHeight + 2 uu both ways: up in its step-up and
## down in its floor test. Also the deepest drop the moves not yet ported stay
## on their feet over (Player.try_step_down(), floor_snap_length).
@export var max_step_down_height: float = 0.35
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
## [ME:CONFIRMED decompile N5 §0.2] TdMove.ShrinkCollision: the collision of a
## move with bUseCustomCollision (Crouch, Slide, Coil, 180TurnInAir,
## LayOnGround, AirBarge, MeleeCrouch, MeleeSlide; Move.use_custom_collision)
## is CollisionHeight 61 uu, a half height, so 1.22 m tall.
@export var custom_collision_height: float = 1.22

@export_group("Jump")
## TdMove_Jump.BaseJumpZ = 630 uu/s. [ME:CONFIRMED decompile 15.7] The jump
## REPLACES the vertical speed with this (times the mobility multiplier);
## Pawn.JumpZ is never read. With the falling integrator's doubled gravity the
## flat jump peaks at 630^2 / 3200 = 1.24 m after 0.394 s and lands after
## 0.7875 s -- what the corpus measured (02 §2.4).
@export var base_jump_z: float = 6.3
## TdMove_Jump.JumpAddXY = 100 uu/s. [ME:CONFIRMED decompile 15.7] Added along
## the FACING, and only when the body is already moving forward faster than
## 10 uu/s -- a standing jump gets nothing, a backward jump gets nothing.
## Nothing hands it back on landing; Landing caps the landing speed against
## the take-off speed instead (LandingConfig.landing_speed_reduction).
@export var jump_add_xy: float = 1.0

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
## PhysicsVolume.GroundFriction: [ME:CONFIRMED decompile 15.2] the UE3 default
## 8, which the acceleration functions add back as Velocity * GroundFriction *
## 0.1 and the walking physics takes off as drag.
@export var ground_friction: float = 8.0
## Godot-specific: the downward bias every grounded move writes each tick so
## is_on_floor() does not flicker across seams. The original's PHYS_Walking
## has no equivalent because it does not need one.
@export var floor_snap_speed: float = 2.0

@export_group("Speed energy")
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
## Read by the ported acceleration (PawnAcceleration) in the original's own
## role.
@export var speed_max_base_velocity: float = 4.0
## [ME:CONFIRMED 02 §2.1] the three factors below as VALUES. [ME:INFERRED] as
## a FORMULA: energy accrues at (active factor / sprint factor) per second,
## so ordinary running is 30/30 = 1.0 -- not verified against bytecode.
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
## SpeedTurnDecelerationFactor: [ME:CONFIRMED decompile, ini] 10, TdPawn's CDO
## and DefaultGame.ini [TdGame.TdPawn]. [ME:CONFIRMED emulated 15 §15.2] read
## by GetSprintAcceleration as Velocity * 10 * |aTurn| / 32768, aTurn in
## rotator units per frame (PawnAcceleration.sprint()). DO NOT recalibrate it.
@export var speed_turn_deceleration_factor: float = 10.0

@export_group("Landing")
## [ME:CONFIRMED 03 §3.1] TdMove_Landing CDO, as fall HEIGHTS (not impact
## speeds): 200 / 300 / 530 uu. LandingMove measures them from
## Player.enter_falling_height.
@export var skill_roll_landing_height: float = 2.0
@export var soft_landing_height: float = 3.0
@export var hard_landing_height: float = 5.3
## [ME:CONFIRMED 03 §3.1] DefaultPawnMovement.ini sets EnterToFallingZSpeed =
## -200 uu/s under TdMove_Falling, but [ME:CONFIRMED decompile] the class
## declares no such field, so nothing reads it: the exit from Jump to Falling
## is TdPhysicsMove.ExitToFallingZSpeed, -400.
## Kept for the moves not yet ported that hand to Falling on it (DodgeJump).
@export var enter_to_falling_z_speed: float = -2.0
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

## How far the view may turn off the held heading, in degrees, before a body
## standing still turns to catch up -- and how far that turn goes. The head
## and the spine follow the view up to HeadLook's own limit (a quarter turn);
## past this the legs take one step round by this much, on the pack's Turn90
## clip, and the head is back inside its range. FIRST PERSON ONLY, both by
## the owner's call: from inside the head a body that swivels whole under
## every glance reads as welded to the mouse, while from outside a body that
## keeps its heading however far the camera goes round is how you get to see
## the character's face.
@export var turn_in_place_angle_deg: float = 90.0

## How long the heading takes to come round by turn_in_place_angle_deg,
## seconds. Quick: the legs are what the eye reads the facing from, and a
## heading that crawled round over the whole clip left the player looking
## at their own back. The clip is NOT tied to this -- see the next dial.
@export var turn_in_place_time: float = 0.3

## Playback rate of the Turn90 clip while stepping round, as a multiplier on
## the authored pace. The clip plays through at this rate however fast the
## heading came round above -- lagging the heading a little is fine, the
## owner's call; squeezed to finish with it, the step read as a flinch.
@export var turn_in_place_clip_scale: float = 1.0

## In first person the heading may never fall further than
## turn_in_place_angle_deg behind the view, whatever the mouse does: a flick
## past it drags the legs round at once, and the step above turns the rest.
## The owner: a little clipping beats seeing your own back. Third person is
## the opposite call and is not clamped -- see _drive_body_yaw().

## How long after a hazard's hit, or after a landing lockout releases, the
## player cannot be staggered again. PROJECT-DEFINED: the original's wire
## hurts by DamagePerSec and stumbles on its touch (Player.touch_barbed_wire());
## this window is the cadence this project's STAGGER damage is dealt at.
##
## A wire volume renews its STAGGER every tick the body is in it, and without
## a window each of those would hurt again and empty the budget again. Armed at
## the hit (Player.take_hazard_hit()) and when a lockout that began as one
## ends.
@export var stagger_immunity_time: float = 1.0
## Seconds a hazard's hit takes to fade from the screen. PROJECT-DEFINED.
@export var hurt_flash_time: float = 0.6

## [ME:CONFIRMED 13.1] Measured off the HUD. A hard landing costs 15 of these
## whatever the height, a fatal fall costs exactly all of them -- so a full
## health death and a wounded one are the same code path with no special case
## -- and a lethal volume costs ten times that, which is not a damage figure
## but the sentence "nothing survives this".
@export var max_health: float = 100.0

## [ME:CONFIRMED 13.1] Seconds after the last damage before health starts
## coming back.
##
## THE DELAY IS WHAT MAKES THE WOUNDED PICTURE VISIBLE. The climb back is only
## a few seconds wide; shortening this does not make recovery snappier, it
## deletes the feedback that the player was hurt at all.
@export var health_regen_delay: float = 5.0

## Health per second once the delay is up. Flat, not a curve.
##
## [ME:CONFIRMED] measured by the owner in the original: 20. 13.1 gives 35;
## the measurement wins, DO NOT put 35 back.
@export var health_regen_rate: float = 20.0

## [ME:CONFIRMED 13.1] What a fatal fall costs, which is exactly a full bar.
@export var fatal_fall_damage: float = 100.0

## [ME:CONFIRMED 13.1] What a volume the level marked lethal costs. Ten times
## a full bar on purpose: it does not mean "a very big hit", it means there is
## no state in which the player walks away.
@export var lethal_volume_damage: float = 1000.0
