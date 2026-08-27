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
## [ME:CONFIRMED 06 §6.2] SpeedModifier, per-move values in 05-动作库总览.md.
@export var speed_modifier: float = 1.0

## Multiplier on PawnConfig.base_friction while this move is active.
## [ME:CONFIRMED 06 §6.2] FrictionModifier, e.g. Slide 0.1, WallRun 0.05.
@export var friction_modifier: float = 1.0

## Seconds before this same move may be entered again.
## [ME:CONFIRMED 06 §6.2] RedoMoveTime, e.g. WallRun 0.15, WallKick 1.0.
@export var redo_move_time: float = 0.0

## Look-angle clamp while this move is active, as (pitch, yaw, roll) in
## RADIANS. The original stores these as UE3 integer angles where
## 65536 = 360 degrees (see 09 §9.2), e.g. WallRun's
## `MinLookConstraint = (-13000, -16384, -32768)` -> pitch -71.4 deg,
## yaw -90 deg, roll -180 deg. Converted at authoring time, not at runtime.
## [ME:CONFIRMED 06 §6.2, 04 §4.1]
@export var min_look_constraint: Vector3 = Vector3(-PI, -PI, -PI)
@export var max_look_constraint: Vector3 = Vector3(PI, PI, PI)

## Whether the clamp above is applied at all.
## [ME:CONFIRMED 06 §6.2] bConstrainLook.
@export var constrain_look: bool = false

## Whether the yaw half of the clamp is measured against a fixed world yaw
## captured on entering the move, rather than against the current facing.
## [ME:CONFIRMED 04 §4.1] bUseAbsoluteYawConstraint = True on WallRun.
## The VISIBLE body holds still while the view turns, so only the head follows.
##
## The body must not visibly rotate during a slide or a grab -- only the
## head -- or the legs (slide) or whole body (grab) swing about and it looks
## ridiculous.
##
## PRESENTATION ONLY, and deliberately so. The collision body still turns with
## the view, exactly as it always has, and every probe and threshold reads the
## same numbers -- this counter-rotates BodyRoot so the model's WORLD yaw stays
## put, which is the trick _drive_body_yaw() already uses for the standing turn.
## This is a pure visual effect on the model; it does not lock the character's
## real facing.
##
## The head then turns on its own: HeadLook is fed the angle between the view
## and the visible body, so freezing the body IS what asks the head to turn.
@export var freeze_visual_yaw: bool = false

## Whether the CHEST may take its share of a head turn while this move runs.
##
## TRUE ALMOST EVERYWHERE, and false is the interesting case. HeadLook splits a
## look between spine, neck and head so that turning to look at something reads
## as a person rather than an owl -- but the split assumes the shoulders are free
## to move. A hanging body's are not: the arms end at hands that are bolted to a
## ledge, so a chest that rotates takes them with it.
##
## The upper body follows a head turn with a 15 degree spine twist by default;
## DISABLE it during Grab, or the arms rotate along with it and clip through
## the wall.
@export var allows_spine_twist: bool = true

@export var absolute_yaw_constraint: bool = false

## When set, the PITCH clamp is not a fixed band but relaxes as the view turns
## away from the facing the constraint was captured at: min_look_constraint at
## zero yaw, easing toward pitch_min_turned_away at the edge of the yaw range.
##
## Hanging is the case this exists for. Facing the wall there is nothing below
## to look at and the arms are overhead, so the view is pinned above level --
## but a player who has turned to look BACK from the ledge is checking the drop
## they are about to let go into, and a clamp that still refuses to look down
## makes that impossible. A single rectangle cannot express both cases: refuse
## looking down at the wall, allow looking down away from it.
##
## [ME:CONFIRMED] TdMove_Grab carries four separate look-constraint pairs
## (HangFree, Slope, ShimmyAroundCorner, ShimmyAroundCornerFree) rather than
## one. [ME:UNKNOWN] which one applies when -- the dump does not say what
## selects between them. The INTERPOLATION between them is this project's own
## mechanism, not read from the original.
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
## it, both hands are on the ledge and the view stays up. The switch sits at
## around a quarter turn.
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
## [ME:CONFIRMED 06 §6.2] bCheckForGrab / bCheckForVaultOver /
## bCheckForWallClimb.
@export var check_for_grab: bool = false
@export var check_for_vault_over: bool = false
@export var check_for_wall_climb: bool = false

## Whether this move may hand off to Zipline when the body is inside a
## zipline InterestLine's volume. Set on the airborne moves only:
## [ME:CONFIRMED 05 §5.5] a cable is caught from a jump, never walked into
## (TdMove_IntoZipLine).
@export var check_for_zipline: bool = false

## Whether this move may hand off to Swing inside a SWING InterestLine's
## volume. Airborne moves only, same reasoning as check_for_zipline.
@export var check_for_swing: bool = false

## Whether this move may hand off to Ladder inside a LADDER InterestLine's
## FRONT volume. Airborne moves only -- see check_for_zipline for why. The
## ground and wall-run entries do not read this flag at all: [ME:CONFIRMED 05]
## a ladder is catchable while walking or wall-running unconditionally (the
## frontal fan is the only gate there), so those two moves ask
## LadderMove.front_side_allows() directly rather than through a switch that
## would always be true for them.
@export var check_for_ladder: bool = false

## Whether Q may start a turn out of this move.
##
## DEFAULT TRUE, and the exceptions are what carry the meaning. The rule is
## that Q works almost everywhere -- anywhere the legs are not tied up --
## which is the original's MovementGroup showing through: a move in
## MG_TwoHandsBusy or mid-animation has no spare limbs to spin on. Turning it
## off is therefore a statement about a specific move, and belongs on that
## move's own config beside its other facts, not in a list somewhere else
## that has to be kept in step with the move set.
##
## The GROUPING is project-defined: the original expresses it as a
## MovementGroup enum this project has not modelled, and modelling one for a
## single consumer would be a mechanism rather than a fact.
@export var allows_turn: bool = true

## Whether the yaw fan above is stated for a wall on the LEFT and should be
## mirrored when the wall is on the right.
##
## Only wall running sets it, and only because its fan is one-sided: the view
## may swing away from the wall and not into it, so which sign is legal depends
## on which side the wall is. The original expresses this by having a
## WallRunLeft and a WallRunRight whose only difference is the mirrored fan;
## this project has one move, so the mirroring lives here.
##
## The MECHANISM is project-defined. The values it mirrors are not.
@export var mirror_yaw_by_wall_side: bool = false
