class_name LadderConfig
extends MoveConfig

# The original's TdMove_Ladder. Pipes and ladders are one mechanic (05's
# family of "along a line" interactions): a vertical (or inclined)
# InterestLine climbed with W/S, entered only from its authored FRONT
# (InterestLine.front(), a frontal 180-degree fan open to grounded, airborne
# AND wall-running bodies alike), and left by crouching, jumping (Task 5), or
# reaching the top (Task 7).
#
# MOST DIALS BELOW ARE UNMEASURED INITIAL GUESSES. This project has little ME
# reference footage for ladders/pipes (see task-4-brief.md), so unlike the
# zipline and swing configs beside it almost nothing here was read off the
# original; the fields that WERE carry an [ME:...] tag of their own. The owner
# dials the rest once footage exists.

func _init() -> void:
	# Rides a world-space InterestLine target. See MoveConfig.holds_world_path.
	holds_world_path = true
	# Both hands are on the rungs: the body stays squared to the ladder and
	# only the head turns -- ✅ the owner: "得锁人物模型，只允许转头，和grab一样."
	# See MoveConfig.freeze_visual_yaw.
	freeze_visual_yaw = true
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

## ⚠️ To-be-measured initial guess. Vertical distance from the capsule centre
## up to where the raised hands grip the line. The LINE is the ladder the
## hands hold: its top point is the highest grip, not the highest place the
## body's centre goes -- ✅ the owner: "顶端点应该是手可以碰到的最高点，而不是
## 胶囊中心，另外手碰到梯子最顶端就该进行爬上检测了."
@export var hand_height: float = 0.75
## Degrees off the ladder's front the view may turn and still take the jump-
## off (Task 5) rather than being refused. Mirrors GrabConfig's own pairing
## of jump_angle_deg against "looking at it" vs. "looking away".
@export var jump_angle_deg: float = 45.0
## Launch speed of a jump off the ladder (Task 5). Copied from GrabConfig's
## own jump_speed as a starting point -- letting go of a ladder and letting
## go of a ledge are the same kind of shove.
@export var jump_speed: float = 6.3
## Degrees above the horizontal a jump off the ladder launches at, whatever
## the camera's pitch. Same reading as GrabConfig.jump_pitch_deg.
@export var jump_pitch_deg: float = 45.0
## How close to the top (Task 7) counts as having reached it, metres.
@export var top_exit_reach: float = 1.2
## How far below the line's top the deck behind it may be, metres.
## PROJECT-DEFINED. Many of the original's ladders run on past the deck they
## serve, rails and all, so the deck can sit well under the top grip. The
## probe fires BEHIND the ladder (toward the wall), never down its own rungs,
## so reaching further only risks finding a floor far below a ladder with no
## deck at all -- which is why this stays a limit rather than going unbounded.
@export var top_exit_max_drop: float = 2.0
## [ME:CONFIRMED] the carry off the top of a ladder onto the deck behind it
## runs 1 s, not the 2 s first guessed here. Seconds. CharacterAnimator
## stretches ClimbUp_1m to match (see LadderMove.scripted_duration()), so this
## is the clip's playback length too.
@export var top_exit_time: float = 1.0

## How far above the LANDING point the carry's bezier peaks. ✅ 0, at the
## owner's direction ("不用搞凸起，参考一下GrabPullUp"): the monotonic
## rise-then-level curve, ScriptedMove._control_height()'s own degenerate
## case and exactly what the pull-up plays. With the landing already the
## NEAREST standable point there is no lip left to clear over. Raise only
## if some future geometry needs a hump after all.
@export var top_exit_apex_lift: float = 0.0

## ⚠️ To-be-measured initial guess. Where the bezier's control point sits
## between the ends: 1 puts it above the START (a steep rise hugging the
## ladder, flattening onto the deck -- the shape the owner drew in red),
## 0 above the landing. See ScriptedMove.begin()'s control_bias.
@export_range(0.0, 1.0) var top_exit_control_bias: float = 0.7
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
## Metres a body may sit BEHIND the line's front plane and still catch it. A
## pipe standing further off its wall than the capsule radius puts a body
## running along that wall beside the pipe, slightly behind its front plane
## (Stormdrain: pipe 0.58 m off the ring wall, wall-run body 0.45 m off it).
## DO NOT raise it to stand_off or past: a body standing off the back of a
## free-standing ladder at climbing distance must still be refused.
@export var back_slack: float = 0.25
