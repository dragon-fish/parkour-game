class_name PlayerState
extends Node

# One movement state. A state decides its own outgoing transitions: every
# question of the form "can I go from X to Y" has exactly one answer, and it
# lives in X's physics_update.

## Returned from physics_update to stay in the current state.
const KEEP: StringName = &""

# State names live here rather than on Player. GDScript resolves class_name
# globals at parse time, so if the states referenced Player.AIR while Player
# referenced GroundState, the two scripts would form a cycle and fail to
# resolve. Keeping the names on the state layer makes the dependency
# one-directional: Player -> states -> PlayerState.
const GROUND: StringName = &"Ground"
const AIR: StringName = &"Air"
const SLIDE: StringName = &"Slide"
const VAULT: StringName = &"Vault"
const LEDGE: StringName = &"Ledge"

## Set by Player before the state machine starts. Untyped for the same
## reason: a typed reference would reintroduce the cycle.
var player
var config: MovementConfig

func enter(_previous: StringName) -> void:
	pass

## Returns the name of the state to switch to, or KEEP to stay.
func physics_update(_delta: float, _input: MoveInput) -> StringName:
	return KEEP

func exit() -> void:
	pass
