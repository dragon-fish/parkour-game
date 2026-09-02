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
	# The drift check compares the current position against a world-space
	# anchor captured on entry. See MoveConfig.holds_world_path.
	holds_world_path = true
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

## HOW FAR A KICK CARRIES YOU UP WITH NO RUN-UP. See climb_height_running for
## the other end, and read both notes together -- this one records how the
## reading got here.
##
## The first version of this move priced height off `AddOnSpeed2DHeight` and
## `AddOnSpeedZHeight`, worth nothing standing still. The owner corrected it --
## "the climb height seems unrelated to speed, but the rate of ascent is
## affected" -- and it became a constant. The measurements above put it back in
## the middle: speed buys a little height (1.30 -> 1.47) and a lot of contact
## point (up to 1.24), which is why it FEELS unrelated while not being.
##
## 🎯 So the two AddOn fields may mean exactly what their names say after all.
## ❓ Still not consumed here -- these numbers came from a stopwatch and a HUD,
## not from the CDO, and wiring the CDO fields in would be swapping a measured
## curve for an unmeasured one.
##
## Speed still shows up in the climb twice, which is why it feels like it
## matters: it raises the rate of ascent (below), and a running jump makes
## CONTACT higher up its arc than a standing one, so the same fixed climb
## starts from a higher place. The owner reported exactly that second effect
## independently -- "when taking off with a run-up, the kick starts higher".
##
## ✅ MEASURED. Standing still pressed against a wall, the owner's Z goes 0.93
## to 2.23 -- and pressed against it, contact happens on the first airborne
## tick, so that 1.30 m IS the climb and nothing else.
##
## ⚠️ THE RUN-UP CASE WAS FILED UNDER THIS NUMBER TOO, AND SHOULD NOT HAVE BEEN.
## Near full speed the owner measured Z going 0.93 to 3.64, i.e. SZD 2.71.
## Contact there happens near the jump's own apex (base_jump_z 6.3 against
## gravity 16 is 1.24 m), so 1.24 + 1.30 = 2.54 -- and the seven per cent left
## over was written off as measurement slop on a reading taken at "near" full
## speed.
##
## ✅ IT WAS NOT SLOP. The owner re-measured deliberately: "贴墙0速Climb
## SZD=1.30，高速最佳化Climb SZD~=2.71". Optimised, not approximate, and it
## lands on the same 2.71. A residual that survives being measured on purpose
## is a term, not noise -- see climb_height_running.
##
## WHAT SURVIVES OF THE OLD READING IS THE BIGGER HALF, and it is still the
## interesting one: most of what a run-up buys is the CONTACT POINT, not the
## climb. 1.24 of the 1.41 m difference between the two measurements is the
## jump arc, exactly as the owner originally described -- "when taking off with
## a run-up, the kick starts higher". What changed is that the climb itself
## grows a little too, instead of not at all.
##
## Was ⚠️ 1.6 while it was a guess.
@export var climb_height: float = 1.3

## HOW FAR A KICK CARRIES YOU UP AT run_speed_limit, the other end of the same
## dial.
##
## 📐 DERIVED FROM THE TWO MEASUREMENTS, and it is subtraction rather than a
## model: SZD 2.71 minus the 1.24 m the jump arc puts under the contact point
## leaves 1.47 m of climb. climb_height (1.30) is the same subtraction with
## nothing under it, because a body pressed against the wall makes contact on
## its first airborne tick.
##
## ⚠️ THE INTERPOLATION BETWEEN THEM IS INVENTED. Two points fix a line only if
## something says the relationship is linear, and nothing does -- these are the
## endpoints, and linear is the cheapest curve through them. ✅ The owner, on
## proceeding anyway: "具体数值我之后测，但你可以按这个感觉调". So this is a
## dial with the ends measured and the middle assumed, which is worth knowing
## before anyone reads a mid-speed climb as evidence of anything.
@export var climb_height_running: float = 1.47

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
