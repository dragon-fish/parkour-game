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
##   scene    PackedScene -- RESERVED, NOT READ BY ANYTHING YET. A later plan
##            wires the growth show to a per-lesson obstacle; filling this in
##            today does nothing.
@export var lessons: Array[Dictionary] = []

## The level's wrap, if it has one. A standing obstacle must take the same
## step the body takes when it crosses an edge.
@export var wrap: TorusWrap

## How far along the player is. The lesson at this index is the one currently
## being taught; equal to lessons.size() once every lesson is passed.
var index: int = 0

signal lesson_passed(passed_index: int)
signal finished

## Obstacles currently in the world, oldest first. They travel together on a
## wrap, so this list is what the wrap talks to.
var _standing: Array[TutorialObstacle] = []

func _ready() -> void:
	if player != null and player.move_manager != null:
		player.move_manager.move_changed.connect(_on_move_changed)
	attach_wrap()

func _on_move_changed(_from: StringName, to: StringName) -> void:
	# An empty table never announces finished. A level author who forgot to
	# fill in the lesson table gets a level that sits still, which he notices
	# immediately. The alternative (silently declaring completion) makes the
	# tower rise for no reason, which is far harder to diagnose.
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
	# The top-of-function guard (index >= lessons.size() -> return) is what
	# makes this reachable exactly once: the tick after index reaches
	# lessons.size(), every later call returns before this line.
	if index >= lessons.size():
		finished.emit()

## Connects the level's wrap. Idempotent, and safe with no wrap at all -- a
## level without one simply never shifts.
func attach_wrap() -> void:
	if wrap != null and not wrap.wrapped.is_connected(_on_wrapped):
		wrap.wrapped.connect(_on_wrapped)

## Takes ownership of an obstacle already in the scene, so it travels on a
## wrap. Used by the level builder and by tests.
func adopt(obstacle: TutorialObstacle) -> void:
	if obstacle != null and not _standing.has(obstacle):
		_standing.append(obstacle)

func _on_wrapped(offset: Vector3) -> void:
	for obstacle in _standing:
		if is_instance_valid(obstacle):
			obstacle.shift_by(offset)
