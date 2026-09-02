class_name TutorialDirector
extends Node

# Teaching progress. The spine of the tutorial is a curve of ATTITUDES (see
# the spec); this class counts where along it the player is, and builds the
# one lesson he is being taught.
#
# The signal that advances it already exists: MoveManager announces every
# transition. So a lesson is passed by DOING the thing, never by walking into
# a trigger volume and never on a timer.
#
# A LESSON IS ONE BLOCK. Growth and collapse act on the GrowingSolid that owns
# the whole of a lesson's geometry, never on the individual meshes under it --
# a lesson that faded in piece by piece would read as a level loading rather
# than as the world drawing itself.
#
# References point down and backwards only:
#
#   TutorialObstacle          the placement anchor
#     GrowingSolid            this block's grow/collapse timing
#       Content               the lesson's own geometry, from its own .tscn
#
# GrowingSolid holds a TutorialObstacle; the obstacle must never hold a
# GrowingSolid back, or the two class_name globals form a parse-time cycle.
# This class holds both.

## The body being taught. Assigned by the level scene.
@export var player: Player

## One entry per lesson, in order. Named fields rather than a positional
## array because this table will grow more of them (a hint line, a shortcut
## flag):
##   teaches  StringName -- the Move whose first performance passes this lesson
##   scene    PackedScene -- optional. The lesson's own level file; only its
##            Content subtree is taken (see LessonContent). A row without one
##            teaches nothing visible but still advances, so the table can be
##            authored a row at a time and stay walkable.
@export var lessons: Array[Dictionary] = []

## The level's wrap, if it has one. A standing obstacle must take the same
## step the body takes when it crosses an edge.
@export var wrap: TorusWrap

## Optional. A scene whose root is a TutorialObstacle, used as the placement
## anchor so a level can preset spawn_distance and friends. Without one a bare
## TutorialObstacle is built at runtime with its own defaults.
@export var obstacle_template: PackedScene

## How long a lesson takes to draw itself into existence. Tuning value; the
## constraint it must satisfy is TutorialObstacle.spawn_distance's, that the
## show finishes before the player arrives.
@export var grow_time: float = 1.2

## How long a passed lesson takes to leave. Tuning value.
@export var collapse_time: float = 0.9

## How far along the player is. The lesson at this index is the one currently
## being taught; equal to lessons.size() once every lesson is passed.
var index: int = 0

signal lesson_passed(passed_index: int)
signal finished

## One entry per lesson currently in the world, oldest first. Named fields
## because this grows: see naming-config-fields.
##   lesson    int -- index into `lessons`, or -1 for an adopted stranger
##   obstacle  TutorialObstacle -- the placement anchor
##   growth    GrowingSolid -- owns this block's grow/collapse timing; null
##             for an adopted obstacle, which grows on nobody's clock
##   leaving   true once it has been told to collapse
var _live: Array[Dictionary] = []

func _ready() -> void:
	if player != null and player.move_manager != null:
		player.move_manager.move_changed.connect(_on_move_changed)
	attach_wrap()
	_build_lesson(index)

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
	_collapse_lesson(passed)
	_build_lesson(index)

## Connects the level's wrap. Idempotent, and safe with no wrap at all -- a
## level without one simply never shifts.
func attach_wrap() -> void:
	if wrap != null and not wrap.wrapped.is_connected(_on_wrapped):
		wrap.wrapped.connect(_on_wrapped)

## Takes ownership of an obstacle already in the scene so it travels on a
## wrap. Used by the level builder and by tests.
##
## An adopted obstacle is a stranger: this class did not build it, does not
## own its growth, and never collapses it. It is here for the wrap and for
## nothing else, so its entry carries no block and an index no lesson can
## match.
func adopt(obstacle: TutorialObstacle) -> void:
	if obstacle == null:
		return
	for entry in _live:
		if entry.get(&"obstacle") == obstacle:
			return
	_live.append({lesson = -1, obstacle = obstacle, growth = null, leaving = false})

## The anchor of the lesson currently being taught, or null.
func current_obstacle() -> TutorialObstacle:
	for entry in _live:
		if not entry.get(&"leaving", false):
			return entry.get(&"obstacle")
	return null

## How many lessons are in the world, including one still collapsing.
func live_count() -> int:
	return _live.size()

func _on_wrapped(offset: Vector3) -> void:
	# EVERYTHING STILL VISIBLE TAKES THE SAME STEP THE BODY TAKES. A block left
	# behind lands a period away from where the player last saw it, and the
	# crossing announces itself.
	for entry in _live:
		var obstacle: TutorialObstacle = entry.get(&"obstacle")
		if is_instance_valid(obstacle):
			obstacle.shift_by(offset)

## Builds the lesson at `at` and starts it growing. Silently does nothing for
## a row with no scene yet -- the table is authored a row at a time, and a
## half-filled table must still be walkable.
func _build_lesson(at: int) -> void:
	if at < 0 or at >= lessons.size():
		return
	var scene: PackedScene = lessons[at].get(&"scene")
	if scene == null:
		return
	var content: Node3D = LessonContent.take(scene)
	if content == null:
		push_error("TutorialDirector: lesson %d has a scene with no Content node" % at)
		return

	var obstacle: TutorialObstacle
	if obstacle_template != null:
		obstacle = obstacle_template.instantiate() as TutorialObstacle
	else:
		obstacle = TutorialObstacle.new()
	obstacle.name = "Lesson%d" % at
	obstacle.player = player
	# Keep clear of whatever is still leaving, so a player who turns round
	# right after finishing does not get the next block on top of the last.
	var avoid: Array[TutorialObstacle] = []
	for entry in _live:
		var other: TutorialObstacle = entry.get(&"obstacle")
		if is_instance_valid(other):
			avoid.append(other)
	obstacle.avoid = avoid
	add_child(obstacle)

	var growth := GrowingSolid.new()
	growth.name = "Growth"
	growth.grow_time = grow_time
	growth.collapse_time = collapse_time
	growth.obstacle = obstacle
	# CONTENT FIRST, THEN INTO THE TREE. GrowingSolid gathers the meshes it
	# fades in its own _ready(), which runs the moment it is parented under
	# something already in the tree. Content hung on afterwards is not in that
	# list, and the lesson stands there fully opaque while the fade runs over
	# an empty set.
	growth.add_child(content)
	obstacle.add_child(growth)

	_live.append({lesson = at, obstacle = obstacle, growth = growth, leaving = false})
	growth.gone.connect(_on_block_gone.bind(obstacle))
	growth.begin()

## Sends a lesson's block away. It stays in _live until it has finished
## leaving, because it is still visible and still has to travel on a wrap.
func _collapse_lesson(at: int) -> void:
	for entry in _live:
		if entry.get(&"lesson", -1) != at:
			continue
		entry[&"leaving"] = true
		var growth: GrowingSolid = entry.get(&"growth")
		if is_instance_valid(growth):
			growth.collapse()
		return

func _on_block_gone(obstacle: TutorialObstacle) -> void:
	for i in _live.size():
		if _live[i].get(&"obstacle") == obstacle:
			_live.remove_at(i)
			break
	if is_instance_valid(obstacle):
		obstacle.queue_free()
