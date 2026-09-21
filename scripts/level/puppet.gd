class_name Puppet
extends Node3D

# One of the original's animated characters, stood in the level: its own mesh
# on its own skeleton, under this node, with the AnimSequences a cutscene plays
# on it (tools/me_level, from skeletal_glb.py). It does nothing by itself. A
# Matinee that animates it says where its sequence is every tick, and this
# puts the body in the pose that moment has.
#
# POSED, NOT PLAYED. The sequence owns the clock -- it is paused with the
# game, runs at the rate Kismet sets, can be sought and reversed -- and an
# AnimationPlayer left to run beside it would agree with it only by luck.

## The body's AnimationPlayer, found once.
var _player: AnimationPlayer = null


func _ready() -> void:
	var found := find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		_player = found[0] as AnimationPlayer
		_player.speed_scale = 0.0


## `plays`: [{animation, start, offset, rate, loops}] sorted by start, as the
## original's InterpTrackAnimControl has them; `time` is the sequence's own.
## What plays at `time` is the last entry begun by then -- before the first one
## begins, the first, held at its start.
func pose(plays: Array, time: float) -> void:
	if _player == null or plays.is_empty():
		return
	var play: Dictionary = plays[0]
	for candidate: Dictionary in plays:
		if float(candidate["start"]) <= time:
			play = candidate
	var animation := StringName(str(play["animation"]))
	if not _player.has_animation(animation):
		return
	var seconds: float = _player.get_animation(animation).length
	var into: float = maxf(time - float(play["start"]), 0.0) * float(play["rate"]) + float(play["offset"])
	into = fposmod(into, seconds) if bool(play["loops"]) and seconds > 0.0 else clampf(into, 0.0, seconds)
	if _player.current_animation != animation:
		_player.play(animation)
	_player.seek(into, true)
