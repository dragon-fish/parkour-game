class_name MoveAnim
extends RefCounted

# A move's custom animation as the move logic sees it: a name and the moment
# it ends. [ME:CONFIRMED decompile TdMove.PlayMoveAnim, TdPawn.OnAnimEnd]
# Many of the original's moves take their timing from the end of the sequence
# they play -- OnCustomAnimEnd sets the next move -- and only for the sequence
# the move's CurrentCustomAnimName names, so playing another replaces it.
#
# The length is the original's first-person SequenceLength divided by |rate|
# (anims/moves_to_anims.md), never a clip of this project's: body_scene is
# optional, and the timing must not depend on which clip happens to stand in.
# What the body shows is CharacterAnimator's business.

var name: StringName = &""
## Seconds since play().
var elapsed: float = 0.0
var _length: float = 0.0

## Plays `anim`, `length_1p` seconds long at rate 1, at `rate` (a negative rate
## plays it backwards in the same time).
func play(anim: StringName, length_1p: float, rate: float = 1.0) -> void:
	name = anim
	elapsed = 0.0
	_length = length_1p / maxf(absf(rate), 1e-6)

func stop() -> void:
	name = &""
	elapsed = 0.0
	_length = 0.0

func is_playing(anim: StringName = &"") -> bool:
	return name != &"" and (anim == &"" or anim == name)

## Advances by `delta`. Returns the name of the animation that ended on this
## tick, or an empty name.
func advance(delta: float) -> StringName:
	if name == &"":
		return &""
	elapsed += delta
	if elapsed < _length:
		return &""
	var ended: StringName = name
	stop()
	return ended
