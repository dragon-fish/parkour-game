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
