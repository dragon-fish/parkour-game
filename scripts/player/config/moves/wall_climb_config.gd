class_name WallClimbConfig
extends MoveConfig

# The original's TdMove_WallClimb: running straight at a wall and kicking
# vertically up it. Distinct from TdMove_WallRun, which is the same contact
# taken at an angle and carried ALONG the wall instead of up it.
#
# The owner reported this as missing. It was worse than missing: Probes had no
# ray that could see a wall in front of the player at all (wall_query() fires
# only to the left and right), so no amount of state machinery would have
# reached it. See Probes.wall_ahead_query().
#
# WHAT PICKS THIS OVER A WALL RUN IS THE ANGLE, and the three confirmed
# thresholds partition the quarter-circle between them without overlapping:
#
#     0-33 deg   head-on      -> this move          WallClimbingVerticalStartAngle
#     33-57 deg  glancing     -> wall run, forward  WallRunningForwardMaxStartAngle
#     57-60 deg  hysteresis   -> neither
#     60-90 deg  alongside    -> wall run, strafe   WallRunningStrafeStartAngle
#
# That they tile exactly is the reason to believe the reading: the original
# has ONE bCheckForWallClimb flag covering both moves, so something downstream
# of that flag has to choose, and the angle is the only candidate with numbers
# attached.

func _init() -> void:
	# ✅ TdMove_WallClimb has all three set, so a kick up a wall can still turn
	# into a mantle or a vault the moment either becomes possible. This is what
	# makes "kick up, catch the lip" one continuous motion rather than two
	# moves the player has to aim separately.
	check_for_grab = true
	check_for_vault_over = true
	# ✅ FrictionModifier = 0.3.
	friction_modifier = 0.3

@export_group("Entry")

## ✅ `WallClimbingVerticalStartAngle = 33.0` degrees, read as the angle from
## head-on -- 0 means running straight at the wall.
##
## The alternative reading (33 degrees from the wall's FACE, i.e. 57 from
## head-on) is ruled out by arithmetic: it would put this move's band exactly
## on top of the wall run's forward band, and the original cannot have two
## moves competing for the identical range with no tie-break anywhere in the
## data. Read from head-on, the three thresholds tile cleanly.
@export var vertical_start_angle: float = deg_to_rad(33.0)

## ✅ `MinWallHeight = 180` uu. A wall shorter than this is something to vault
## or mantle, not something to kick up.
@export var min_wall_height: float = 1.8

## How far ahead the forward ray looks for a wall.
##
## ⚠️ PROJECT-DEFINED. Measured from the body's CENTRE, so one capsule radius
## (0.40 m) is already spent inside it: 0.6 m means the body is within about
## 0.2 m of touching. Deliberately shorter than the reach a grab is allowed
## (0.8 m) -- the owner's account of the original is that you touch the wall
## and then climb it, and a longer reach here reads as being sucked in.
@export var check_distance: float = 0.6

## Whether a MOTIONLESS kick is allowed. It is.
##
## This started life as a min_speed gate mirroring wall_running_min_speed, on
## the reasoning that you have to be moving at a wall for a kick to mean
## anything. THE OWNER CORRECTED IT FROM THE ORIGINAL: standing still, pressed
## against a wall, W and space climbs. Kept as a named field rather than deleted
## so the corrected behaviour is visible rather than merely absent.
##
## What replaces the speed gate is INTENT: a climb needs the player either
## moving at the wall or pressing into it. Without that, jumping straight up
## while happening to stand near a wall would climb it.
@export var allow_standing_kick: bool = true

@export_group("Climb")

## ✅ `WallClimbingGravity = 800` uu/s^2 against this project's own 1600 --
## exactly half, expressed as a scale so it tracks any retune of gravity.
##
## This one number is the whole feel of the move. The owner described it,
## before seeing any of the data, as "like being stuck to the wall".
@export var gravity_scale: float = 0.5

## ✅ `WallClimbingVerticalFriction = 6.0`. Bleeds the run-up's horizontal speed
## away while the climb converts it into height, so a climb finishes with the
## body stopped against the wall rather than still drifting along it.
@export var horizontal_friction: float = 6.0

## HOW FAR A KICK CARRIES YOU UP. A constant -- speed does not buy height.
##
## The first version of this move had it the other way round: height bought
## with speed, worth nothing standing still, priced off `AddOnSpeed2DHeight`
## and `AddOnSpeedZHeight`. THE OWNER CORRECTED IT FROM THE ORIGINAL, in one
## sentence that rules out that whole reading: "the climb height seems
## unrelated to speed, but the rate of ascent is affected".
##
## So the two AddOn fields are ⚠️ NOT height at all in the sense assumed, or
## they add to a base that lives in PHYS_WallClimbing's own code rather than in
## the CDO. Either way they are not consumed here any more, and what they do
## mean is now an open question rather than a settled one.
##
## Speed still shows up in the climb twice, which is why it feels like it
## matters: it raises the rate of ascent (below), and a running jump makes
## CONTACT higher up its arc than a standing one, so the same fixed climb
## starts from a higher place. The owner reported exactly that second effect
## independently -- "when taking off with a run-up, the kick starts higher".
##
## ⚠️ 1.6 m is about a body height: enough that a kick puts a lip that was out
## of reach into grabbing range, which is the whole job.
@export var climb_height: float = 1.6

## How fast the body goes up, with no run-up at all.
##
## ⚠️ DERIVED, not chosen: set so that a motionless kick, decelerating under
## the half gravity above, arrives at climb_height with nothing to spare. That
## is what makes a standing climb read as "just about makes it" while costing
## no separate tuning knob of its own -- see WallClimbMove.rise_speed().
@export var rise_speed_bonus: float = 1.0

## The run speed at which rise_speed_bonus is fully earned. ⚠️ PROJECT-DEFINED,
## matching PawnConfig's own ground speed closely enough that ordinary running
## reaches it.
@export var run_speed_limit: float = 6.5

## ✅ `WallClimbingMaxDistance2D = 120` uu as a VALUE. ❓ as a role: the field
## name says a horizontal distance and says nothing about from what.
##
## Read here as drift from the point of contact -- a climb is meant to go
## straight up, and one that has wandered 1.2 m sideways is no longer on the
## wall it started on. Cheap to be wrong about: at the friction above, the
## horizontal speed is gone long before this is reached, so it only ever fires
## on a genuinely odd climb.
@export var max_drift: float = 1.2

## How hard the body is held against the wall while climbing, so a contact that
## is nearly-but-not-quite square does not drift out of ray range.
##
## ⚠️ PROJECT-DEFINED, copied from `WallRunConfig.wall_stick_force`, which
## exists for the same reason and is documented there.
@export var wall_stick_force: float = 0.5
