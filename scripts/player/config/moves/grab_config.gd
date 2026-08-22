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
@export var mantle_duration: float = 0.42
## Horizontal speed granted on top after a mantle.
@export var mantle_exit_speed: float = 2.0
## How far past the ledge edge the mantle's landing point sits, so the body
## ends up standing ON the platform rather than teetering right at its lip.
## Mirrors SpeedVaultConfig.vault_exit_forward's role for VaultState.
@export var mantle_forward_offset: float = 0.4
## Peak height of the vertical arc ScriptedMove.advance() adds over the
## straight line from the hang position to the mantle's landing point, so the
## body reads as climbing up and over the lip instead of clipping through it.
## Mirrors SpeedVaultConfig.vault_arc_height's role for VaultState -- see
## ScriptedMove's own note on why the arc is a per-call value rather than a
## shared literal.
@export var mantle_arc_height: float = 0.3

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

## Upward speed of a jump off a hang, in metres/second.
##
## ✅ `TdMove_GrabJump.GrabJumpOffZHeight = 160` uu.
##
## ⚠️ READ AS A SPEED, and the field name argues the other way -- "Height", not
## the "Z" that every confirmed velocity in the family uses (`BaseJumpZ`,
## `SpringBoardJumpZ`). Taken as a speed it is 1.6 m/s; taken as a rise it is
## 1.6 m, and the two are nothing alike. Speed is the reading kept, because
## `TdMove_WallClimb180TurnJump.JumpOffZHeight = 250` under the rise reading
## would launch a turn-jump 2.5 m straight up, which the original plainly does
## not do.
##
## 📌 Either way this is a SHOVE, not a boost. The owner expected it to feel
## like the wall kick, and horizontally it does -- 2 to 4 m/s against the kick's
## own 3.0 -- but the kick goes UP at 5.8. Letting go of a ledge drops you.
@export var jump_speed_up: float = 1.6

## Push away from the wall at the smallest angle that allows a jump.
##
## ✅ `TdMove_GrabJump.GrabJumpPushAwayMinSpeed = 200` uu/s.
@export var jump_push_min: float = 2.0

## Push away from the wall with your back fully turned to it.
##
## ✅ `TdMove_GrabJump.GrabJumpPushAwayMaxSpeed = 400` uu/s.
##
## ⚠️ WHAT MOVES BETWEEN THE TWO IS INFERRED. The CDO gives a min and a max and
## no driver, and the turn angle is the only quantity this move has that varies
## continuously -- so it is lerped from jump_angle_deg to a full 180. It reads
## the way the move plays: the further you have turned your back on the wall,
## the harder you shove off it.
@export var jump_push_max: float = 4.0

func _init() -> void:
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # legs busy: hanging. Which way you face is the wall's business.
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
