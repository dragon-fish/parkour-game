class_name BalanceConfig
extends MoveConfig

# The original's TdMove_Balance. Walking a pipe or a beam.
#
# The five pendulum fields below are the ones LedgeWalkConfig does NOT have,
# and they are the whole difference between the two moves.

## How far the body is turned off the line's own tangent, degrees. 0 puts the
## shoulders along the beam, which is what makes W/S the travel keys here and
## leaves A/D free to be the correction. See LedgeWalkConfig for the other case.
@export var body_yaw_offset_deg: float = 0.0

@export var foot_snap_height: float = 0.35

## How long the magnet catch takes to pull the body onto the beam. Same shape
## and same number as LadderConfig.fade_in_time -- the rest of the "along a
## line" family's own fade dial.
@export var fade_in_time: float = 0.15

## Seconds for the lean to grow by a factor of e.
##
## [ME:CONFIRMED] TimeToCounter = 0.8 -- the NUMBER only. Reading it as a
## divergence time constant rather than as a correction window is this
## design's: exponential divergence has no grace period, only a time
## constant, and that is what explains why being a fraction late is
## hopelessly late.
@export var divergence_time: float = 0.8

## Correction authority of A/D against the lean.
## [ME:CONFIRMED] ControlInfluence = 1.5.
@export var correction_gain: float = 1.5

## How much the ENTRY speed magnifies the one-off starting lean.
## [ME:CONFIRMED] SpeedInfluence = 2.5. It magnifies the entry offset ONLY --
## the divergence afterwards is speed-independent, which is what reconciles
## "faster is harder" with the owner's own measurement that the wobble itself
## has nothing to do with speed.
@export var entry_speed_influence: float = 2.5

## The starting lean a body gets even at a standstill.
##
## MUST STAY NON-ZERO. An inverted pendulum sitting exactly on its apex never
## falls, and the owner measured that standing still on a beam DOES lose
## balance. This is what denies the player that perfect apex.
@export var base_wobble: float = 0.02

## Lean turned into real lateral displacement off the beam's centreline,
## metres per unit of lean.
##
## [ME:INFERRED] The CDO's GravityInfluence = 0.3. The dump gives names and
## numbers but no formulae, and read as "instability coefficient" this field
## would be a second name for the divergence rate divergence_time already sets.
## Taken instead as the sibling of CameraInfluence -- both 0.3, both the rate
## that turns lean into one of its consequences. That makes falling off a
## GEOMETRIC result (the feet leave the beam) rather than one more threshold.
## See docs/superpowers/specs/2026-08-30-balance-and-ledge-walk-design.md.
@export var gravity_influence: float = 0.3

## How far the body may drift off the centreline before the feet miss, metres.
@export var beam_half_width: float = 0.14

## Largest camera roll the lean may reach in first person, degrees.
##
## THIS IS WHAT CameraInfluence BECAME. [ME:CONFIRMED] the CDO's
## CameraInfluence = 0.3 is a rate from lean to roll, but the lean this move
## reports is already normalised against beam_half_width, so a second rate
## multiplying it would just be a smaller number to reach the same angle. One
## angle you can dial beats two coefficients whose product you have to work out.
##
## DIRECTION: the horizon tips toward the side the body is falling to, the
## same way a head tips when the shoulders under it do -- judged in play on
## scenes/debug_levels/balance_course.tscn. The opposite (horizon tipping
## away from the fall) reads as the camera fighting the lean instead of
## reporting it.
@export var max_camera_roll_deg: float = 12.0

## Largest body lean the skeleton shows, degrees.
@export var max_body_lean_deg: float = 18.0

## Share of that lean the HIPS take. Small on purpose: everything below the
## waist hangs off this bone, so a large share swings the feet off the beam.
## The project has no leg IK, so this is what stands in for planted feet.
@export var hips_lean_share_deg: float = 4.0

## How far the FOV closes in at full lean, degrees. Subtracted from whatever
## the speed-driven FOV asks for.
@export var fov_squeeze_deg: float = 10.0

func _init() -> void:
	# [ME:CONFIRMED] SpeedModifier 0.34 -> 720 * 0.34 = 244.8 uu/s = 8.81 km/h,
	# which matches the owner's own HUD reading to two decimals. The multiplier
	# applies to the GroundSpeed CONSTANT, not to the speed carried in: arriving
	# at 25.9 km/h still drops you to 8.8.
	speed_modifier = 0.34
	# [ME:CONFIRMED] RedoMoveTime = 0.5 -- half a second before a beam may be
	# re-entered, so jumping off does not get you sucked straight back on.
	redo_move_time = 0.5
	constrain_look = true
	# [ME:CONFIRMED] MinLookConstraint (-13000, -6000, -32768) -> pitch -71.4,
	# yaw +-32.96. NARROWER THAN THE LEDGE'S OWN FAN, matching "the camera runs
	# along the beam". MaxLookConstraint's pitch of 25000 (~137 deg) is outside
	# UE3's own +-16384 pitch range and its meaning is unknown -- capped at 90
	# here. DO NOT put 137 back without evidence.
	min_look_constraint = Vector3(deg_to_rad(-71.4), deg_to_rad(-32.96), -PI)
	max_look_constraint = Vector3(deg_to_rad(90.0), deg_to_rad(32.96), PI)
	freeze_visual_yaw = true
	# [ME:CONFIRMED] MG_TwoHandsBusy.
	allows_turn = false
