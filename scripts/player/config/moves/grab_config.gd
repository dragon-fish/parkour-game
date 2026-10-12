class_name GrabConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Grab (the ledge hang/mantle
# move).

## Source: 04 §4.2 `TdMove_WallClimb.MinWallHeight = 180` uu. ✅ The lowest
## thing worth grabbing rather than vaulting -- and it dovetails with the
## vault table, whose own ceiling is 1.92 m (05 §5.7).
@export var min_wall_height: float = 1.8
## Highest ledge top, measured from the player's feet, that can still be
## grabbed. PROJECT VALUE, no counterpart in the original -- no ✅/⚠️ marker
## applies to a number with no source uu. The original needs no upper bound
## here because anything above 1.92 m leaves the vault table entirely and
## routes into the wall-climb chain instead (05 §5.7: TdMove_WallClimb ->
## TdMove_IntoGrab -> TdMove_GrabPullUp). This project deliberately excludes
## wall climb, so without a ceiling of its own the grab would silently inherit
## every surface that chain was meant to handle; 2.8 m is that backstop.
@export var ledge_max_height: float = 2.8
## Source: 09 §9.1 comparison table / appendix A1 `TdPawn.LedgeFindDistance =
## 350` uu. ✅ (The field lives on the Pawn CDO, not in the vault table.)
## Notably longer than this project's own 1.0 m reach: the original starts
## looking for a ledge from much further out, which is part of why its grabs
## read as deliberate rather than as last-instant saves.
@export var ledge_find_distance: float = 3.5
## Source: 04 §4.2 `MinLegdeZNormal = 0.707` -> 45 degrees. ✅ (The original
## misspells the field; corrected here per the naming convention.)
## ❓ No consumer wired: Probes.ledge_query() rejects an unwalkable ledge top
## against PawnConfig.walkable_floor_z (0.71), which is the same 45 degrees to
## within a third of a degree, and one number governing "what counts as a
## surface you can stand on" is better than two that can drift apart.
@export var min_ledge_z_normal: float = 0.707
## How long the mantle motion takes.
## ✅ THE OWNER: "我们的 GrabPullUp 速度太快了，它不应该比 VaultOver 还快."
##
## 📌 AND THE ORIGINAL HAS NO NUMBER TO COPY. TdMove_GrabPullUp carries no
## duration field at all, which says the length comes from the ANIMATION -- so
## the reference points are the vaults beside it: vault_over and vault_onto are
## 0.65 s, VaultOverHigh 1.03, VaultOntoHigh 1.17. A pull-up that undercut the
## cheapest of those was rewarding the slowest way over a ledge.
##
## 🎯 It also has to be slow enough for the speedrun glitch to be WORTH doing.
## ✅ The owner again: "攀边扭头略大于 45° 对着墙沿起跳...能把超级慢的 GrabPullUp
## 转换为更快的 VaultOver." A technique that saves a twentieth of a second is not
## a technique anyone would learn.
##
## 🎯 AND THE ANIMATION IS THE ANSWER, not a feel dial. "No duration field" is
## not an omission -- it says the length is whatever the clip is. So this is
## ClimbUp_2m's own 1.300 s, played at 1x, and CharacterAnimator fits the clip to
## it rather than the other way round.
##
## ✅ The owner asked for that clip and for "近 2s": "GrabPullUp 还是太快了...ME 里
## 体感将近 2s 呢，这个动画也得换成 ClimbUp_2m." 1.3 is what this pack has --
## ClimbLedge is 0.633 and ClimbUp_1m 0.667, both far too brisk to read as
## hauling a body over a lip.
##
## 📌 It also makes the speedrun glitch worth learning, which is its own check on
## the number: converting a pull-up into a VaultOver now saves 0.65 s rather than
## a twentieth of a second.
@export var mantle_duration: float = 1.3
## Horizontal speed granted on top after a mantle.
@export var mantle_exit_speed: float = 2.0
## How far past the ledge edge the mantle's landing point sits, so the body
## ends up standing ON the platform rather than teetering right at its lip.
## Mirrors SpeedVaultConfig.vault_exit_forward's role for VaultState.
@export var mantle_forward_offset: float = 0.4

## How much of the pull-up is UP before any of it is forward, 0..1.
##
## ✅ THE OWNER, with a drawing of the path: "脚本弧线不对，它的趋势应该是先垂直向上
## 然后再往前送，而不是一个完美的弧线，否则人会穿墙."
##
## ⚠️ A SYMMETRIC ARC CUTS THE CORNER, AND THE CORNER IS THE WALL. One eased
## curve driving all three axes is a fine description of a VAULT -- the body
## really does go up and over in one motion, and the thing it is arcing over is
## below it. A pull-up is the opposite shape: the obstacle is the face you are
## hanging on, so any forward travel spent before the crown clears the lip is
## spent inside it.
##
## 1.0 is the full hook. See ScriptedMove.begin(), where 0 reduces to the single
## curve every other scripted move still uses.
## ✅ BACK TO ZERO, at the owner's direction after playing the composite: "我觉得
## 这一版曲线改得挺糟糕的，要不然先改回之前的单段程序化曲线，反正都是手K关键帧偏移，
## 越简单的运动曲线反而对我来说越容易."
##
## 🎯 And that is a better argument than the one it overturns. The three-segment
## path was reasoning about where the obstacle is; hand-keyed offsets solve the
## same problem directly, and they are far easier to author against a curve you
## can predict than against one with two knees in it. A base curve that needs
## explaining is a base curve the keys have to fight.
##
## The machinery stays -- ScriptedMove.begin() still takes a lead, and 0 runs the
## old code path verbatim rather than an equivalent of it -- so this is one
## number away from coming back if the keying says it should.
## ⚠️ NOT ZERO ANY MORE, and this is the day the composite was kept for. ✅ THE
## OWNER: "stepup 和 GrabPullUp 还是直线？"
##
## 🎯 A SYMMETRIC ARC IS THE WRONG SHAPE HERE, not merely a smaller one. A bump
## added to a straight line peaks in the MIDDLE OF THE JOURNEY, and a pull-up's
## obstacle is at its NEAR END -- so the body would swing away from the wall at
## half height, which is the one direction it cannot go. The composite is rise,
## flat crossing, settle, and that is what climbing onto something is.
##
## 📌 NO NEW DERIVATION NEEDED. peak_height() is already max(from, to) plus the
## arc, so with no arc a pull-up rises to the height of the top it is climbing
## onto and then goes forward onto it. The number that was missing was never a
## clearance -- it was the shape.
## 📌 NOW IT IS THE BEZIER'''S CONTROL POINT, slid back from the end toward the
## start: 1 puts it directly over the start and the curve bulges away from the
## wall before swinging in; lower pulls the whole line in against the face.
## ✅ The owner, drawing the tighter line: "我希望它整体往内部偏一点." Tuned by eye.
## How high the pull-up's peak sits above the ledge, in metres. See
## SpeedVaultConfig.vault_over_apex_above_top.
##
## 📌 0.9 is where it already was: the pull-up ENDS standing on the ledge, half a
## standing capsule above it, so the higher end was setting the peak on its own.
@export var mantle_apex_above_top: float = 0.9

@export var mantle_control_bias: float = 0.7

## How the pull-up's travel is shaped: 1 is a straight line at a constant speed,
## 2 is the ease-out this move used to have.
##
## ✅ THE OWNER, hand-keying against it: "不如让胶囊走匀速直线，否则我还得对抗那个特别
## 奇怪的曲线." See ScriptedMove.begin(), and
## docs/capsule-leads-presentation.md for why the simple answer keeps winning
## here.
@export var mantle_path_ease: float = 1.0

## How fast the hands travel along a ledge while shimmying, in metres/second.
##
## ✅ THE OWNER, measured in the original: "横爬速度是 2.15 km/h，平均 1s 爬一下，
## 然后缓差不多 0.3s 换手." 2.15 km/h is 0.597 m/s.
##
## 📌 AND IT SETTLES AN EARLIER READING THAT LOOKED WRONG AND WAS. The first
## number off the HUD was 18 km/h, which would have put a hand-over-hand shimmy
## between the original's Run (400 uu/s) and Sprint (630). The suspicion at the
## time was that TdMove_Grab's `PawnPhysics = PHYS_None` leaves the pawn's
## velocity un-integrated, so the HUD was still showing the speed carried INTO
## the grab. Hanging still and re-reading confirmed exactly that.
##
## 📌 It also agrees with the clips, which were the only source before this:
## UAL1's Climb_Left and Climb_Right are 0.87 s for one reach-and-pull, and
## 0.87 s per half a shoulder-width is about 0.6 m/s.
##
## ⚠️ THE ORIGINAL IS NOT CONTINUOUS AND THIS IS. 2.15 km/h is the AVERAGE over a
## cycle the owner clocked as roughly 1 s of travel and 0.3 s of changing hands
## -- so the original moves at nearer 0.78 m/s and then stops dead, twice a
## stride. This travels at a constant 0.597. Reproducing the stutter is a feel
## job for later; the distance covered is already right.
@export var shimmy_speed: float = 0.6

## Dead zone on the sideways stick before a shimmy starts, 0..1.
##
## Wider than a stick's own noise floor on purpose: while hanging, the same
## axis is a hair away from doing nothing at all, and a body that creeps along
## the ledge because a key was brushed reads as a bug rather than as input.
@export var shimmy_deadzone: float = 0.3

## How far above the ledge top the sideways probe starts, in metres.
##
## It has to clear whatever lip, railing or moulding sits on the edge, and it
## has to stay under any overhang above it. 0.3 m is comfortably both on the
## geometry this project builds.
@export var shimmy_probe_lift: float = 0.3

## How much the ledge top may change height over one shimmy step and still
## count as the same ledge, in metres.
##
## This is the knob that stops a shimmy from walking the hands up a staircase
## of ledges: the hanging body is placed for ONE height, and a step up or down
## that the body does not follow would leave it hanging from nothing. Tight on
## purpose.
@export var shimmy_edge_tolerance: float = 0.15

## How wide the hanging body is, measured from its centre line, in metres.
##
## ✅ THE OWNER: "能不能给横爬障碍的探测加一个身体宽度，现在是角色的中心撞到障碍才会
## 被阻挡，但其实人的手已经进入墙里了."
##
## ⚠️ WIDER THAN THE CAPSULE, deliberately. current_capsule_radius() is 0.4, and
## that is the COLLISION body -- a cylinder around the torso. A hanging person is
## not that shape: the arms are up and out, and the leading hand reaches past the
## shoulder it hangs from. Probing at the capsule's own radius therefore lets the
## hand travel a good fifteen centimetres into a wall before the torso notices.
##
## 📌 It is a HALF-width because the probe fires from the centre line in the
## direction of travel: only the leading side matters.
@export var shimmy_body_half_width: float = 0.55

## How far above the ledge top the hand-height probe fires, in metres.
##
## Just clear of the surface: level with the anchor the ray grazes the top it is
## standing on and reports the ledge as its own obstacle, and much higher than
## this it starts clearing things the hands would actually meet.
@export var shimmy_grip_lift: float = 0.06

## How long a ninety-degree corner takes to travel around, in seconds.
##
## ✅ THE OWNER, timing the original: "外 90 转角好像大概 1s 转过去，期间锁镜头，
## 可能是怕穿帮."
##
## 📌 A whole second is a long time to hold a player still, and it is meant to
## be: this is the one moment of a shimmy where the body is not against the wall
## it is hanging from, and the original spends the time rather than cheat it.
@export var corner_duration: float = 1.0

## How long the shimmy is refused after a corner completes, in seconds.
##
## ✅ `TdMove_Grab.DisableShimmyTime = 0.6`.
##
## 🔶 The field's PURPOSE is inferred from its value and this placement: a
## corner leaves the hands a hand's width from the corner they just rounded, so
## without a pause a wobble on the stick walks them straight back around it, and
## then around again. 0.6 s after a 1.0 s turn makes one corner a 1.6 s
## uninterruptible passage, which matches how deliberate the original feels.
@export var corner_lockout: float = 0.6

## How far below the lip the corner probes fire, in metres.
##
## A face is BELOW an edge, not level with it: a ray at the anchor's own height
## grazes the top surface and reports the ledge as its own wall. 0.3 m is under
## any lip or moulding and well above the hanging body's own crown.
@export var corner_probe_drop: float = 0.3

## How full the corner's swing is, as a multiple of the distance to L -- the
## point where the two hang lines cross, i.e. the sharp corner the path would
## have if it turned on a dime. 1.0 puts both of the cubic's control points
## exactly on L.
##
## PROJECT-DEFINED, and 1.0 is DERIVED rather than dialled: L is the one point
## that keeps the ordinary hanging stand-off (ledge_back_offset minus the
## anchor's own inset) from BOTH faces at once, so a path aimed at it is a path
## that hangs off the corner the way it hangs off a flat wall. On the 4 m test
## block that measures 0.320 m of clearance from the corner point against a
## flat-face 0.35.
##
## The straight lerp this replaced measured 0.067 m on the same corner: the
## body went through the wall, head first. DO NOT go back to lerping the two
## hang poses -- they sit on perpendicular faces and the chord between them
## cuts the convex corner they share.
##
## Turning this UP widens the swing monotonically (1.1 -> 0.346 m, 1.2 ->
## 0.361 m). An earlier attempt anchored the bow at the chord's own midpoint
## instead, where the same knob was NOT monotonic -- 0.3 measured tighter than
## 0.0 -- which is why the control points hang off L rather than off the chord.
@export var corner_sweep: float = 1.0

## How far past the corner the outside-corner probe looks back from, in metres.
##
## It has to start in the OPEN AIR beyond the corner -- a ray beginning inside
## geometry reports nothing at all -- and still be close enough that the face it
## finds is the corner's own rather than something across the street.
@export var corner_probe_reach: float = 0.6

## How far the view must be turned off the wall before jump pushes off it
## instead of pulling up, in degrees.
##
## ✅ `TdMove_GrabJump.GrabAllowedJumpAngle = 45.0`, and it comes as a PAIR:
## `TdMove_GrabPullUp.GrabAllowedPullUpAngle` is 45 as well. Looking at the wall
## climbs it; looking away from it leaves it.
##
## ✅ The owner reported this as "past 90 degrees" from play and then said what
## to do about the discrepancy: "有实测数据就按数据来，我只能用手感跟你描述."
## So the CDO number stands and the 90 is recorded as the feel it was offered as.
@export var jump_angle_deg: float = 45.0

## How far the view may be turned off the wall and still pull UP, in degrees.
##
## ✅ `TdMove_GrabPullUp.GrabAllowedPullUpAngle = 45`, the other half of the pair
## jump_angle_deg is one of. Looking at the wall climbs it; looking away from it
## leaves it; and the two numbers being equal is what makes the split clean
## rather than leaving a band where both fire or neither does.
##
## ✅ THE OWNER, on why the pull-up needs the gate and not just the jump: "grab
## 期间如果镜头扭动超过 45°，按 W 就不要触发 GrabUp，ME 里也是这么处理的，因为玩家
## 一般都是回头同时按 W+空格."
##
## 📌 That last clause is the whole point. Forward-and-jump is one gesture, not
## two, so an ungated pull-up does not merely coexist with the hang jump -- it
## WINS, every time, because it is asked on the same tick with the same keys
## down. Without the angle, the jump is unreachable by the input people use.
##
## 🎯 AND IT IS NOT REALLY AN ANGLE, WHICH IS THE BETTER MODEL AND THE OWNER'S:
## "ME 里扭头大于 45° 会变成单手攀附，很多事情就解释的通，此时无法 AD，也无法
## GrabUp，因为这两种动作都要求 2 hands free."
##
## One state change, two consequences, instead of two rules that happen to share
## a number -- and the CDO agrees from its own side: TdMove_Grab carries
## `MovementGroup = MG_TwoHandsBusy`. Past this angle the body is hanging by one
## arm, so it can neither travel along the ledge nor haul itself over one. See

## Half-width of the look fan DURING THE PULL-UP, degrees of full width -- 175
## here, so the view may go 87.5 degrees either side and no further.
##
## The hang itself keeps its own fan; this replaces it only while the body is
## mantling, because that is the stretch with an animation to contradict. With
## no clamp the player can look back over their own shoulder mid-pull and watch
## their back from the inside.
##
## [ME:INFERRED] the original clamps here too -- the owner reports the
## restriction exists -- but the width has NOT been measured. 175 is a placeholder
## chosen to stop the look-behind and nothing more. DO NOT cite it as measured.
@export var pull_up_look_yaw_deg: float = 175.0

## GrabMove._two_handed(), which is where the single predicate lives.
@export var pull_up_angle_deg: float = 45.0

## How far the view may be turned off the wall and still have the shimmy WIN
## the argument, degrees. Past it the turn is read as aiming a jump instead.
##
## [ME:CONFIRMED] the owner, in the original: holding a strafe key does not
## merely survive a turned view, it PULLS THE VIEW BACK. Between
## pull_up_angle_deg and this the shimmy travels and the fan narrows to the
## two-handed angle, which walks the view home; past this the game leaves the
## view alone, because a body looking back over its shoulder is lining up a
## jump off the wall and taking that away would be worse than refusing a
## shimmy.
##
## THE BAND IS RE-READ EVERY TICK, not latched when the key goes down, and it
## needs no latch: the narrowed fan is what stops a held shimmy from ever
## reaching this angle again, so the only way back out is to let go. That also
## gives the other half of the owner's report for free -- press the key at 120
## degrees, turn back under 90 without releasing, and the shimmy simply starts.
@export var shimmy_assist_angle_deg: float = 90.0

## Upward speed added on top of the launch, in metres/second. A dial.
##
## [ME:CONFIRMED] `TdMove_GrabJump.GrabJumpOffZHeight = 160` uu, read as a
## speed. [ME:UNKNOWN] whether the field is a speed at all: Turn180Config reads
## the sibling `TdMove_WallClimb180TurnJump.JumpOffZHeight = 250` as a 2.5 m
## rise, and neither reading is verified.
##
## IT STEEPENS THE LAUNCH rather than aiming it: at a level view the aim is
## jump_min_pitch_deg off the horizontal and the velocity leaves about nine
## degrees above that. What it buys is range -- a jump off a hang reaches about
## a third further with it than without -- and some of the original's ledges
## cannot be crossed without that reach.
@export var jump_speed_up: float = 1.6

## 📌 TRANSCRIBED AND NOT USED, kept because deleting a sourced number loses the
## record of having read it. `TdMove_GrabJump.GrabJumpPushAwayMinSpeed = 200`
## and `MaxSpeed = 400` uu/s, i.e. 2 to 4 m/s away from the wall.
##
## They were live for one commit, as a floor on the away-from-wall component of
## the launch. What retired them is the owner's speedrun glitch: a jump taken
## just past the 45-degree threshold has to travel INTO the wall to throw the
## body over its own ledge, and any floor on leaving the wall fights exactly
## that. Whatever those two fields govern in the original, it is not a component
## the launch direction can be reduced to.

## How fast a jump off a hang launches, along the view, in metres/second.
##
## ✅ THE OWNER, on the CDO-faithful first version: "grab 回头跳给的冲量不太对，应该
## 是往镜头方向一个大跳，如果抬头也会有往上的力，我们的实现就是软绵绵地落下来，这会
## 让 ME 的一些关卡设计无法实现."
##
## ⚠️ A DELIBERATE DIVERGENCE FROM THE TRANSCRIPTION, and the transcription is
## still recorded above rather than deleted. Read literally, GrabJumpPushAwayMin/
## MaxSpeed (2 to 4 m/s) plus GrabJumpOffZHeight (1.6) is a shove off the wall
## that then drops -- which is exactly what they describe as 软绵绵. Their point
## is a design one and it is decisive: a hang jump that cannot carry you
## anywhere makes a class of the original's level geometry unbuildable, so
## whatever those fields mean, they do not mean what the literal reading
## produces.
##
## 6.3 is base_jump_z: a jump is a jump. The wall kick's own magnitude (3.0 out
## and 5.8 up, so about 6.6) lands in the same place from the other direction.
@export var jump_speed: float = 6.3

## The lowest incline a jump off a hang launches at, degrees above the
## horizontal; a view pitched higher launches higher. [ME:INFERRED] from play:
## a level view jumps out at about 45 degrees in the original.
@export var jump_min_pitch_deg: float = 45.0

func _init() -> void:
	# The mantle/corner-shimmy path is a scripted world-space curve. See
	# MoveConfig.holds_world_path.
	holds_world_path = true
	# Climbed over or let go, the fall counts from here. See
	# MoveConfig.fall_counts_from_exit.
	fall_counts_from_exit = true
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # legs busy: hanging. Which way you face is the wall's business.
	# But the look is nearly free, so Q flicks it round. See
	# MoveConfig.q_flicks_view.
	q_flicks_view = true
	# ✅ HangFreeMinLookContraint / HangFreeMaxLookContraint, at 65536 units =
	# 360 degrees:
	#
	#     min (8300, -16384, 0)  ->  pitch +45.6, yaw -90
	#     max (16000, 16384, 0)  ->  pitch +87.9, yaw +90
	#
	# FACING THE WALL the view cannot go BELOW LEVEL: the arms are overhead and
	# there is nothing under the lip to look at. Level, though, not 45 degrees
	# up -- the CDO's HangFree floor is +45.6, which pins the view at the sky
	# and is not what the game does. The owner reports being able to look
	# straight ahead at the wall, and to see a little of the surface above.
	#
	# BUT NOT ONCE TURNED AWAY. A player hangs off a ledge specifically to drop
	# from it, and before letting go they turn and look at what is underneath.
	# A clamp that still refuses to look down makes the whole manoeuvre
	# impossible, so the pitch floor eases open as the view comes round -- see
	# MoveConfig.pitch_relaxes_with_yaw.
	#
	# The original does something of this kind: TdMove_Grab carries FOUR
	# separate look-constraint pairs (HangFree, Slope, ShimmyAroundCorner,
	# ShimmyAroundCornerFree) where every other move has one, and the dump does
	# not record what selects between them. HangFree is the pair used here.
	#
	# ⚠️ The yaw range is the owner's, not the CDO's: they report not being able
	# to turn a full circle either way, at around 170 degrees. The CDO's
	# HangFree pair says +-90, which would be a much tighter fan than what they
	# describe, and its ShimmyAroundCorner pairs reach +-180. Taking the
	# reported figure, since it is the one measured against the actual game.
	constrain_look = true
	# ✅ The owner: hanging, only the head follows the view. ⚠️ They accepted
	# that this may clip in first person and asked for it anyway for now.
	# See MoveConfig.freeze_visual_yaw.
	freeze_visual_yaw = true
	# ✅ THE HANDS ARE ON THE LEDGE, so the shoulders cannot follow the head --
	# see MoveConfig.allows_spine_twist. The arms swung into the wall without
	# this.
	allows_spine_twist = false
	min_look_constraint = Vector3(0.0, -deg_to_rad(170.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(87.9), deg_to_rad(170.0), PI)
	# ⚠️ PROJECT-DEFINED. Turned fully away, the view can look well below level
	# -- far enough to see the ground under the drop.
	# ONE-HANDED PAST A QUARTER TURN. The original switches hold as the player
	# turns away, and only the one-handed hold can look down -- which is what
	# makes "hang, look at the drop, let go" possible at all. Both hands on the
	# ledge, the view stays up.
	#
	# ⚠️ The threshold is the owner's, tuned by feel from 90 to 53 degrees.
	# The CDO's four look-constraint pairs make it clear the original selects
	# between several holds, but not on what.
	pitch_relaxes_with_yaw = true
	pitch_relax_yaw_threshold = deg_to_rad(53.0)
	pitch_min_turned_away = -deg_to_rad(70.0)
	# ⚠️ The CDO also sets bDisableFaceRotation, which this project does not
	# implement (docs/feel-backlog.md 12). Absolute yaw is the stand-in: with
	# the facing pinned, a relative clamp behaves as an absolute one.
	absolute_yaw_constraint = true

	# Was PawnConfig.ledge_regrab_cooldown, a hand-rolled timer Player carried
	# and GrabMove.exit() armed by hand. Same 0.45 s, now expressed the way the
	# original expresses every cooldown (TdMove.RedoMoveTime) and enforced by
	# MoveManager for every move alike, so no caller can forget to arm it and
	# no second cooldown path can grow beside it.
	#
	# DIVERGES FROM SOURCE, deliberately: appendix A1 records
	# `TdMove_Grab.RedoMoveTime = 0.15` -- three times shorter. 0.45 is kept
	# because it is the value this project has actually been played at, and
	# because this project's grab is a single move that covers both the hang
	# and the pull-up, where the original spreads those across TdMove_Grab,
	# TdMove_GrabPullUp and TdMove_GrabTransfer (whose own RedoMoveTime is
	# 0.5). Changing it is a feel decision for the owner, not a transcription
	# fix -- see the spec's own deviation list.
	redo_move_time = 0.45

