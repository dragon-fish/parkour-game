class_name LadderConfig
extends MoveConfig

# The original's TdMove_Ladder. Pipes and ladders are one mechanic (05's
# family of "along a line" interactions): a vertical (or inclined)
# InterestLine climbed with W/S, entered only from its authored FRONT
# (InterestLine.front(), a frontal 180-degree fan open to grounded, airborne
# AND wall-running bodies alike), and left by crouching, jumping (Task 5), or
# reaching the top (Task 7).
#
# ⚠️ EVERY DIAL BELOW IS A TO-BE-MEASURED INITIAL GUESS. This project has no
# ME reference footage for ladders/pipes yet (see task-4-brief.md) -- unlike
# the zipline and swing configs beside it, nothing here carries a ✅ measured
# marker. The owner dials all of these once footage exists.

func _init() -> void:
	# Per-LINE cooldown (Player.note_line_left), same reasoning the rest of
	# the "along a line" family settled on: release one ladder, catch the
	# next at once -- see same_line_redo_time below.
	redo_move_time = 0.0
	# BOTH HANDS ON THE RUNGS, same as the cable and the bar.
	allows_turn = false

## Metres/second the body travels along the line for a held W/S.
@export var climb_speed: float = 1.8
## How long the magnet catch takes to pull the body onto the ladder. Same
## shape as the rest of the family's own fade (see LineMove).
@export var fade_in_time: float = 0.15
## How far the capsule's centre stands off the line, along its front, while
## climbing. NOT IN THE SPEC -- implementation-necessary: without a stand-off
## the capsule's centre rides ON the wall the ladder is mounted to and clips
## straight through it.
@export var stand_off: float = 0.4
## Degrees off the ladder's front the view may turn and still take the jump-
## off (Task 5) rather than being refused. Mirrors GrabConfig's own pairing
## of jump_angle_deg against "looking at it" vs. "looking away".
@export var jump_angle_deg: float = 45.0
## Launch speed of a jump off the ladder (Task 5). Copied from GrabConfig's
## own jump_speed as a starting point -- letting go of a ladder and letting
## go of a ledge are the same kind of shove.
@export var jump_speed: float = 6.3
## How close to the top (Task 7) counts as having reached it, metres.
@export var top_exit_reach: float = 1.2
## How long the top-exit scripted motion takes, seconds.
@export var top_exit_time: float = 2.0
## How far a body may be from a DIFFERENT ladder and still magnet-snap onto
## it (Task 5's jump-to-adjacent-ladder case), metres.
@export var snap_range: float = 4.0
## How long a snap flight from one ladder to another takes, seconds.
@export var snap_flight_time: float = 0.55
## Minimum dot product between the pressed direction and the candidate line,
## i.e. how wide the snap's aiming cone is (0.7 ~= a 45-degree half-angle).
@export var snap_cone_dot: float = 0.7
## How long the ladder just left refuses a re-catch, seconds. Per LINE, not
## per move name -- see LineMove.note_left().
@export var same_line_redo_time: float = 0.6
## Falling faster than this (m/s, positive) the hands cannot catch the
## ladder. No CDO field for ladders; borrowed from the rest of the family's
## own confirmed number, same as SwingConfig does.
@export var fall_limit: float = 6.0
