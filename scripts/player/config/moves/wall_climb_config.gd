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

## ⚠️ PROJECT-DEFINED, mirroring `wall_running_min_speed`: you have to be
## MOVING at the wall for a kick to mean anything. Standing against a wall and
## jumping is a jump, not a climb.
@export var min_speed: float = 2.0

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

## The climb's height is BOUGHT WITH SPEED, and buys nothing without it. There
## is no base term anywhere in the CDO, which is the point: a standing kick
## goes nowhere.
##
## ✅ `AddOnSpeed2DHeight = 60` uu at `AddOnSpeed2DMaxLimit = 650` uu/s, and
## ✅ `AddOnSpeedZHeight = 130` uu at `AddOnSpeedZMaxLimit = 320` uu/s. Each
## contribution ramps linearly with its own speed and saturates at its own
## limit, so the most a climb can ever be worth is 1.9 m.
##
## The Z term is why a kick taken on the way UP out of a jump climbs so much
## further than one taken at the top of the arc -- twice the height for the
## same run-up, which matches how the original rewards jumping early.
@export var run_speed_height: float = 0.6
@export var run_speed_limit: float = 6.5
@export var rise_speed_height: float = 1.3
@export var rise_speed_limit: float = 3.2

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
