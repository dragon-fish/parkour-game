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
const JUMP: StringName = &"Jump"
const SLIDE: StringName = &"Slide"
const CROUCH: StringName = &"Crouch"
const SPEED_VAULT: StringName = &"SpeedVault"
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

## The MoveConfig in force RIGHT NOW. Overridable because the original splits
## a single airborne stretch across two move classes with different probe
## switches -- TdMove_Jump while rising, TdMove_Falling while descending (05
## §5.7 ③) -- and FallingMove reproduces that split without doubling the
## machine. Everything else returns its own cfg.
func current_config() -> MoveConfig:
	return cfg

func enter(_previous: StringName) -> void:
	pass

## Returns the name of the move to switch to, or KEEP to stay.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

func exit() -> void:
	pass
