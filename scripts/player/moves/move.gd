class_name Move
extends Node

# One movement action -- the Godot counterpart of the original's TdMove. A
# move decides its own outgoing transitions: every question of the form "can
# I go from X to Y" has exactly one answer, and it lives in X's
# physics_update.
#
# Names live here rather than on Player. GDScript resolves class_name globals
# at parse time, so if the moves referenced Player.FALLING while Player
# referenced WalkingMove, the two scripts would form a cycle and fail to
# resolve. Keeping the names on this layer makes the dependency
# one-directional: Player -> moves -> Move.
#
# Names follow the original's own move classes (minus the Td prefix):
# TdMove_Walking, TdMove_Falling, TdMove_Slide, TdMove_Crouch,
# TdMove_SpeedVault, TdMove_Grab, TdMove_WallRun.

## Returned from physics_update to stay in the current move.
const KEEP: StringName = &""

const WALKING: StringName = &"Walking"
const FALLING: StringName = &"Falling"
const FALL_UNCONTROLLED: StringName = &"FallUncontrolled"
const JUMP: StringName = &"Jump"
const LANDING: StringName = &"Landing"
const SKILL_ROLL: StringName = &"SkillRoll"
const SLIDE: StringName = &"Slide"
const CROUCH: StringName = &"Crouch"
const SPEED_VAULT: StringName = &"SpeedVault"
const INTO_GRAB: StringName = &"IntoGrab"
const GRAB: StringName = &"Grab"
const WALL_RUN: StringName = &"WallRun"

## Set by Player before the manager starts. Untyped for the same reason the
## names live here: a typed reference would reintroduce the cycle.
var player

## The whole config tree, for the Pawn-wide values every move needs.
var config: MovementConfig

## This move's OWN declared parameters. Assigned by Player at registration
## from the matching MovementConfig field.
var cfg: MoveConfig

## The MoveConfig in force RIGHT NOW. Overridable so a move whose own config
## legitimately varies mid-move (without a state transition) has somewhere to
## express that -- FallingMove used to override this to pick between
## config.jump and config.falling by velocity.y sign, before Jump became its
## own real state (Task 1: airborne-state-chain) made that split unnecessary.
## No move overrides this today; it is a retained hook, not dead code -- see
## MoveManager._push_look_constraint()'s own note on why it is still read
## every tick rather than only on transition. Everything else returns its
## own cfg.
func current_config() -> MoveConfig:
	return cfg

func enter(_previous: StringName) -> void:
	pass

## Returns the name of the move to switch to, or KEEP to stay.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

func exit() -> void:
	pass
