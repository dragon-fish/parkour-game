class_name LedgeWalkConfig
extends MoveConfig

# The original's TdMove_LedgeWalk. Shuffling along a narrow ledge with your
# back to the wall.
#
# THERE IS NO BALANCE HERE, and that is the whole point of the move. The CDO
# carries none of TdMove_Balance's five pendulum fields -- no GravityInfluence,
# ControlInfluence, SpeedInfluence, TimeToCounter or CameraInfluence -- so a
# ledge cannot be fallen off. All it does is take the speed down to a tenth,
# lock the view and lock the facing. [ME:CONFIRMED] the dumped CDO; see
# docs/mirrors-edge-deep-research/appendix/A1-TdMove-CDO全量.md.
#
# It is a LEVEL PACING TOOL rather than a movement ability: the geometry is
# walkable anyway, and the interest point exists to force the player to slow
# down. SpeedModifier 0.1 is the harshest in the game.

## How far the body is turned off the line's own tangent, degrees. 90 puts the
## shoulders across the line -- back to the wall, shuffling sideways -- which is
## what makes A/D the travel keys here without a single branch in LineWalkMove.
## [ME:CONFIRMED] the first game's LedgeWalk always faces AWAY from the wall;
## only Catalyst added a facing-the-wall variant.
@export var body_yaw_offset_deg: float = 90.0

## How close the feet must be to the line's own height for a catch, metres.
## The reach volume alone is not enough -- InterestLine's radius would swallow a
## body running PAST the ledge at ground level.
@export var foot_snap_height: float = 0.35

func _init() -> void:
	# [ME:CONFIRMED] SpeedModifier 0.10 -> 720 * 0.1 = 72 uu/s = 2.59 km/h.
	speed_modifier = 0.10
	constrain_look = true
	# [ME:CONFIRMED] MinLookConstraint (-14000, -10000, -32768),
	# MaxLookConstraint (16384, 10000, 32768), UE3 angles where 65536 = 360 deg:
	# pitch -76.9..+90.0, yaw +-54.93, roll unconstrained.
	min_look_constraint = Vector3(deg_to_rad(-76.9), deg_to_rad(-54.93), -PI)
	max_look_constraint = Vector3(deg_to_rad(90.0), deg_to_rad(54.93), PI)
	# The body must not swivel to follow the view: the shoulders are square to
	# the wall and a hand is on it. [ME:CONFIRMED] bDisableFaceRotation.
	freeze_visual_yaw = true
	# [ME:CONFIRMED] MG_OneHandBusy -- no spare limbs to spin on.
	allows_turn = false
