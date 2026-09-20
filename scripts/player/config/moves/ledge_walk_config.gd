class_name LedgeWalkConfig
extends MoveConfig

# The original's TdMove_LedgeWalk. Shuffling along a narrow ledge, a hand on
# the wall.
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
#
# Which way the body faces is decided by the view -- back to the wall in first
# person, facing it in third -- see LedgeWalkMove's own header.

## How far the body is turned off the line's own tangent, degrees. 90 puts the
## shoulders across the line -- shuffling sideways -- which is what makes A/D
## the travel keys here without a single branch in LineWalkMove. The MAGNITUDE
## only: which of the two sides across the line it lands on is
## LedgeWalkMove._yaw_offset()'s call, from the wall and the view.
## [ME:CONFIRMED] the first game's LedgeWalk always faces AWAY from the wall;
## only Catalyst added a facing-the-wall variant.
## The body follows the ledge through whatever stands in its way.
##
## [ME:CONFIRMED A1] squeezing through a gap IS a ledge walk in the original,
## and it knows it: ELedgeWalkType is {LWT_Ledge, LWT_NarrowSpace} and
## TdMove_LedgeWalk picks between them with CheckLedgeWalkType(). Nothing in
## its CDO shrinks the capsule or drops collision, so whatever the narrow-space
## case does about the walls lives in native code and cannot be read.
##
## WE DO NOT SPLIT THE TYPES. The capsule is 0.8 m across and the gaps are
## narrower, so a ledge that respects geometry cannot be walked there at all:
## the body is pushed out of the wall every tick and the walk stalls. The line
## is the path and the level author drew it; where it goes, the body goes. A
## per-line narrow-space flag is what to add if a plain ledge ever needs its
## collision back.
@export var pass_through_geometry: bool = true

@export var body_yaw_offset_deg: float = 90.0

## How close the feet must be to the line's own height for a catch, metres.
## The reach volume alone is not enough -- InterestLine's radius would swallow a
## body running PAST the ledge at ground level.
@export var foot_snap_height: float = 0.35

## How long the magnet catch takes to pull the body onto the ledge. Same shape
## and same number as LadderConfig.fade_in_time -- the rest of the "along a
## line" family's own fade dial.
@export var fade_in_time: float = 0.15

## How long the body takes to turn round on the spot when the view switches
## mid-ledge, seconds. The pack's Turn180 clip (1.67 s as authored) is fitted
## to this window by CharacterAnimator._scripted_fit(), and no travel happens
## for its duration. A project dial: the original never switches views.
@export var turn_time: float = 0.5

## Full width, degrees, of the yaw fan the view is held inside in THIRD
## person -- 175 means +-87.5 either side of the body's facing. First person
## keeps the [ME:CONFIRMED] +-54.93 of min/max_look_constraint below: that
## number was measured through the original's eye, and an outside camera
## looking past the body's back at the wall has room the eye never had. A
## project dial; see LedgeWalkMove.look_yaw_half_span().
@export var third_person_look_yaw_deg: float = 175.0

## How far the head turns toward the way the body is shuffling, in degrees,
## while the camera is watching from outside.
##
## THIRD PERSON ONLY. The shoulders are pinned across the line, so a shuffling
## character otherwise stares straight at the wall while travelling sideways,
## which reads as being dragged. In first person the camera follows a head
## node by position, so the same turn would slide the eye sideways for no
## reason the player asked for.
##
## Kept well inside HeadLook's own release curve: this stacks on however far
## the view has already turned, and a total past a quarter turn starts easing
## itself out.
@export var head_turn_deg: float = 40.0

## Where the head's pitch is held, in degrees, while the camera is watching
## from outside. Negative is down. The owner's call: a shuffling body watches
## its own feet on the ledge, not wherever the camera happens to be pitched.
##
## THIRD PERSON ONLY, like head_turn_deg above and for the same reason -- in
## first person the eye IS the head, and pitching it under the player would
## pull the view off wherever they are looking.
@export var head_pitch_deg: float = -10.0

## Playback rate of the sidestep clips (Walk_L / Walk_R) while shuffling,
## as a plain multiplier on the authored pace. Replaces the speed match
## CharacterAnimator._drive_speed() would otherwise apply, which fits a
## walking gait to 0.72 m/s and lands near 0.4x -- far too slow, because a
## shuffle is not a walk: the steps are short and the cadence is not.
## 1.0 is the clip as authored.
@export var shuffle_clip_scale: float = 1.0

## How far the VIEW must have turned off the ledge's normal, in degrees,
## before W/S get a look-relative assist on top of their ordinary (here,
## null) body-relative reading -- see LedgeWalkMove._resolve_look_assist().
## The view is wherever the camera looks: the eye in first person, the
## camera behind the view in third. Looking straight out from the wall, or
## straight at it, and pressing W must still do nothing, which is what the
## gate is for.
@export var look_assist_angle_deg: float = 45.0

func _init() -> void:
	# Rides a world-space InterestLine target. See MoveConfig.holds_world_path.
	holds_world_path = true
	# [ME:CONFIRMED] SpeedModifier 0.10 -> 720 * 0.1 = 72 uu/s = 2.59 km/h.
	speed_modifier = 0.10
	constrain_look = true
	# [ME:CONFIRMED] MinLookConstraint (-14000, -10000, -32768),
	# MaxLookConstraint (16384, 10000, 32768), UE3 angles where 65536 = 360 deg:
	# pitch -76.9..+90.0, yaw +-54.93, roll unconstrained.
	min_look_constraint = Vector3(deg_to_rad(-76.9), deg_to_rad(-54.93), -PI)
	max_look_constraint = Vector3(deg_to_rad(90.0), deg_to_rad(54.93), PI)
	# MEASURED AGAINST THE FACING THE CATCH BEGAN WITH, not against the body's
	# current one. freeze_visual_yaw below holds the visible MODEL still, but
	# the collision body still yaws with the view, so a fan measured against it
	# travels with the view it is supposed to be limiting: reach the edge, keep
	# turning, and it keeps giving. WallRun sets this for the same reason.
	# [ME:CONFIRMED] the CDO expresses the same intent through
	# bDisableFaceRotation + bDisableControllerFacingPawnYawRotation.
	absolute_yaw_constraint = true
	# NO TIMED COOLDOWN, and it is not MoveConfig's neutral default by
	# accident: TdMove_LedgeWalk carries no RedoMoveTime, and the one this
	# move briefly had was lethal -- turn round inside it after walking off an
	# end and the next step lands on a ledge that refuses you, over a mesh
	# with no collider. Walking off an end is guarded by the release latch
	# alone (Player.line_ready()): the line re-catches when the body walks
	# back IN along it, and neither standing at the end nor walking on away
	# from it counts. LineWalkMove.exit() would only arm this on a fall, and a
	# ledge has no fall.
	redo_move_time = 0.0
	# The body must not swivel to follow the view: the shoulders are square to
	# the wall and a hand is on it. [ME:CONFIRMED] bDisableFaceRotation.
	freeze_visual_yaw = true
	# [ME:CONFIRMED] MG_OneHandBusy -- no spare limbs to spin on.
	allows_turn = false
	# The wall is along one side of the body for the whole walk; a shoulder
	# camera on that side is in it. See MoveConfig.centre_shoulder.
	centre_shoulder = true
