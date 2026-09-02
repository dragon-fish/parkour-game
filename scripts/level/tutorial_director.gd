class_name TutorialDirector
extends Node

# Teaching progress. The spine of the tutorial is a curve of ATTITUDES (see
# the spec); this class only counts where along it the player is.
#
# The signal that advances it already exists: MoveManager announces every
# transition. So a lesson is passed by DOING the thing, never by walking into
# a trigger volume and never on a timer.
#
# WHAT A LESSON LOOKS LIKE IS NOT HERE. Obstacle geometry, placement and the
# growth show belong to TutorialObstacle -- this class hands out an index and
# says when it changed.

## The body being taught. Assigned by the level scene.
@export var player: Player

## One entry per lesson, in order. Named fields rather than a positional
## array because this table will grow more of them (a hint line, an obstacle
## scene, a shortcut flag):
##   teaches  StringName -- the Move whose first performance passes this lesson
@export var lessons: Array[Dictionary] = []

## How far along the player is. The lesson at this index is the one currently
## being taught; equal to lessons.size() once every lesson is passed.
var index: int = 0

signal lesson_passed(passed_index: int)
signal finished

var _finished_announced: bool = false

func _ready() -> void:
	if player != null and player.move_manager != null:
		player.move_manager.move_changed.connect(_on_move_changed)

func _on_move_changed(_from: StringName, to: StringName) -> void:
	if index >= lessons.size():
		return
	var lesson: Dictionary = lessons[index]
	if to != lesson.get(&"teaches", &""):
		return
	# ONE STEP PER LESSON, NEVER TWO. Doing it a second time is practice, not
	# progress -- advancing again would skip the next lesson, which the player
	# has not been shown yet.
	var passed: int = index
	index += 1
	lesson_passed.emit(passed)
	if index >= lessons.size() and not _finished_announced:
		_finished_announced = true
		finished.emit()
