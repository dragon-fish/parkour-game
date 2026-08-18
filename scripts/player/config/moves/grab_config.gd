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
