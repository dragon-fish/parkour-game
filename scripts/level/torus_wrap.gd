class_name TorusWrap
extends Node

# The plain has no edges: all four join, so running in any direction never
# reaches a wall and never reaches a horizon. Crossing an edge shifts the body
# one period back along that axis.
#
# THE VOID IS WHAT MAKES THIS INVISIBLE. There is no skyline to disagree after
# the shift, and geometry beyond the collapse radius is not drawn, so the
# player has nothing to compare against. DO NOT give this level a skybox.
#
# Height is never touched. The tower rises out of the plain, and a body
# climbing it must not be dragged back to where it started.

## The body to wrap. Assigned by the level scene.
@export var player: Player

## Distance between opposite edges, in metres. Ground speed is 7.2 m/s
## (sprint is higher), so this is roughly how many seconds of running fit
## between crossings. Tuning value -- drag it in the F1 panel.
@export var period: float = 100.0

## Emitted with the shift that was just applied. Anything holding a world
## position that must stay put RELATIVE TO THE PLAYER listens to this.
signal wrapped(offset: Vector3)

func _physics_process(_delta: float) -> void:
	if player == null or period <= 0.0:
		return
	# THE ONE STATE THAT FORBIDS A WRAP. See MoveManager.current_is_scripted().
	# Scripted moves are short, so waiting one out costs nothing -- and in a
	# void the player cannot tell he was held.
	if player.move_manager != null and player.move_manager.current_is_scripted():
		return
	var offset := _offset_for(player.global_position)
	if offset == Vector3.ZERO:
		return
	player.global_position += offset
	wrapped.emit(offset)

## How far to shift a position to bring it back inside the period. Zero when
## it is already inside.
func _offset_for(position: Vector3) -> Vector3:
	var half: float = period * 0.5
	var offset := Vector3.ZERO
	if position.x > half:
		offset.x = -period
	elif position.x < -half:
		offset.x = period
	if position.z > half:
		offset.z = -period
	elif position.z < -half:
		offset.z = period
	return offset
