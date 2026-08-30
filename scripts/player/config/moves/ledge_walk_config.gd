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

## How long the magnet catch takes to pull the body onto the ledge. Same shape
## and same number as LadderConfig.fade_in_time -- the rest of the "along a
## line" family's own fade dial.
@export var fade_in_time: float = 0.15

## Width, in degrees, of the arc the THIRD-PERSON camera's bearing around the
## player is clamped to, centred on the character's own front (the direction
## the model faces, back to the wall). 160 means +-80 -- an arc that sits
## entirely on the outward side, since the character's back (where the
## unclamped camera would otherwise sit) is the wall. NOT min/max_look_
## constraint below: that is [ME:CONFIRMED] and governs where the PLAYER may
## LOOK; this is the owner's own call and governs where the CAMERA may SIT in
## third person. Widening one must never be read as license to widen the
## other. See CameraRig.set_ledge_camera_arc().
@export var camera_arc_deg: float = 160.0

## How far the VIEW must have turned off the body's own front, in degrees,
## before W/S get a look-relative assist on top of their ordinary (here,
## null) body-relative reading -- see LedgeWalkMove._adjust_along(). Facing
## straight out and pressing W must still do nothing, which is what the gate
## is for.
@export var look_assist_angle_deg: float = 45.0

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
