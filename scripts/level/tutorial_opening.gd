class_name TutorialOpening
extends Node

# The only three lines this tutorial ever says about controls.
#
# THEY TEACH THE GRAMMAR, NOT THREE ACTIONS. Two keys, two directions, and
# context decides what happens -- [ME:CONFIRMED 10] the original's own
# "few keys plus contextual resolution". A player who has understood "press up
# at a wall" needs no further lesson for wall runs, wall kicks or climbs, which
# is why nothing after this says anything about controls at all.
#
# A FOURTH LINE MEANS SOMETHING IS WRONG. If an action cannot be reached
# through up or down, it does not belong in the mandatory set -- it belongs on
# a shortcut, where discovering it is the reward.

## Where the lines go. Optional: a level built without one simply stays quiet.
@export var subtitle: Subtitle

## How long a line stays lit, and the pause after it.
@export var hold: float = 3.0
@export var gap: float = 0.6

signal spoken(index: int)
signal done

var _at: int = -1
var _timer: float = 0.0
var _running: bool = false

## The lines, built fresh each call so a rebind is picked up without anything
## having to invalidate a cache. KEYS COME FROM InputNames -- never spell one
## into the text.
func lines() -> PackedStringArray:
	return PackedStringArray([
		"%s  移动" % InputNames.label(InputNames.MOVE),
		"%s  跳跃 / 向上的动作" % InputNames.label(InputNames.JUMP),
		"%s  蹲下 / 向下的动作" % InputNames.label(InputNames.CROUCH),
	])

func play() -> void:
	if _running:
		return
	_running = true
	_at = -1
	_timer = 0.0
	_advance()

func _process(delta: float) -> void:
	if not _running:
		return
	_timer -= delta
	if _timer <= 0.0:
		_advance()

func _advance() -> void:
	_at += 1
	var all := lines()
	if _at >= all.size():
		_running = false
		done.emit()
		return
	if subtitle != null:
		subtitle.show_text(all[_at], hold)
	spoken.emit(_at)
	_timer = hold + gap
