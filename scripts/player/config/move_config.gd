class_name MoveConfig
extends Resource

# Base class for every move's own parameters -- the Godot counterpart of the
# original's TdMove + TdPhysicsMove default properties (see
# docs/mirrors-edge-deep-research/06-Move状态机架构.md §6.2).
#
# Every default here is DELIBERATELY NEUTRAL: a move that declares nothing
# must behave exactly as it did before this layer existed. Declaring a value
# is how a move opts into being different.

## Multiplier on the ground speed cap while this move is active.
## Source: 06 §6.2 `SpeedModifier`. ✅ confirmed field, per-move values in 05.
@export var speed_modifier: float = 1.0

## Multiplier on PawnConfig.base_friction while this move is active.
## Source: 06 §6.2 `FrictionModifier`. ✅ e.g. Slide 0.1, WallRun 0.05.
@export var friction_modifier: float = 1.0

## Seconds before this same move may be entered again.
## Source: 06 §6.2 `RedoMoveTime`. ✅ e.g. WallRun 0.15, WallKick 1.0.
@export var redo_move_time: float = 0.0

## Look-angle clamp while this move is active, as (pitch, yaw, roll) in
## RADIANS. The original stores these as UE3 integer angles where
## 65536 = 360 degrees (see 09 §9.2), e.g. WallRun's
## `MinLookConstraint = (-13000, -16384, -32768)` -> pitch -71.4 deg,
## yaw -90 deg, roll -180 deg. Converted at authoring time, not at runtime.
## Source: 06 §6.2, 04 §4.1. ✅
@export var min_look_constraint: Vector3 = Vector3(-PI, -PI, -PI)
@export var max_look_constraint: Vector3 = Vector3(PI, PI, PI)

## Whether the clamp above is applied at all. Source: 06 §6.2
## `bConstrainLook`. ✅
@export var constrain_look: bool = false

## Whether the yaw half of the clamp is measured against a fixed world yaw
## captured on entering the move, rather than against the current facing.
## Source: 04 §4.1 `bUseAbsoluteYawConstraint = True` on WallRun. ✅
@export var absolute_yaw_constraint: bool = false

## When set, the PITCH clamp is not a fixed band but relaxes as the view turns
## away from the facing the constraint was captured at: min_look_constraint at
## zero yaw, easing toward pitch_min_turned_away at the edge of the yaw range.
##
## Hanging is the case this exists for. Facing the wall there is nothing below
## to look at and the arms are overhead, so the view is pinned above level --
## but a player who has turned to look BACK from the ledge is checking the drop
## they are about to let go into, and a clamp that still refuses to look down
## makes that impossible. A single rectangle cannot express "cannot look down
## at the wall, can look down away from it".
##
## The original clearly does something of this kind: TdMove_Grab carries four
## separate look-constraint pairs (HangFree, Slope, ShimmyAroundCorner,
## ShimmyAroundCornerFree) rather than one, and the dump does not say what
## selects between them. ⚠️ The INTERPOLATION is this project's own reading.
@export var pitch_relaxes_with_yaw: bool = false

## The pitch floor once the view has turned fully to the edge of its yaw range.
## Only read when pitch_relaxes_with_yaw is set.
@export var pitch_min_turned_away: float = -PI

## How far the view must turn before the pitch floor starts opening at all.
## Below this the declared floor applies unchanged; past it, the floor eases
## toward pitch_min_turned_away across the rest of the yaw range.
##
## Hanging is the case: the original switches to a ONE-HANDED hold once the
## player has turned far enough, and that is the hold that can look down. Under
## it, both hands are on the ledge and the view stays up. The owner puts the
## switch at around a quarter turn.
@export var pitch_relax_yaw_threshold: float = deg_to_rad(90.0)

## How quickly the view is pushed back up when it is below the floor -- which
## happens when the player looks down under the relaxed clamp and then turns
## back toward the wall. Exponential, so a rate rather than a duration.
##
## Pushed rather than clamped: clamping snaps, and the view arriving back at
## level in one frame reads as a glitch rather than as hauling yourself round.
@export var pitch_recover_speed: float = 14.0

## Which environment probes this move runs each tick. The original makes
## these per-move switches rather than hardcoding them in each state's
## update -- which is how "a rising jump can start a wall climb but a fall
## cannot" is expressed as data (05 §5.7 ③: TdMove_Jump has
## bCheckForWallClimb, TdMove_Falling does not).
## Source: 06 §6.2 `bCheckForGrab` / `bCheckForVaultOver` /
## `bCheckForWallClimb`. ✅
@export var check_for_grab: bool = false
@export var check_for_vault_over: bool = false
@export var check_for_wall_climb: bool = false
