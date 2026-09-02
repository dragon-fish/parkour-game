class_name InputNames
extends RefCounted

# What a key is CALLED, for anything that has to say so on screen.
#
# TUTORIAL COPY MUST NAME KEYS THROUGH HERE, NEVER AS LITERALS. The bindings
# here reference KeyboardInputSource's constants directly, so if someone
# changes a key in KeyboardInputSource, it changes everywhere at once. There
# is only one place that says "jump is SPACE" and both the game and the UI
# read from it.

const MOVE := &"move"
const JUMP := &"jump"
const CROUCH := &"crouch"
const WALK := &"walk"
const TURN := &"turn"

## The keys KeyboardInputSource actually polls. This dictionary references
## KeyboardInputSource's constants, so these cannot drift.
const _BINDINGS: Dictionary = {
	JUMP: KeyboardInputSource.JUMP_KEY,
	CROUCH: KeyboardInputSource.CROUCH_KEY,
	WALK: KeyboardInputSource.WALK_KEY,
	TURN: KeyboardInputSource.TURN_KEY,
}

## Movement is four keys, so it has no single keycode and carries its own
## label.
const _MOVE_LABEL := "WASD"

## Shown when copy asks for an action that does not exist. DELIBERATELY UGLY:
## a missing binding should be visible on screen during the first playtest,
## not read as a plausible key.
const _UNKNOWN := "???"

static func label(action: StringName) -> String:
	if action == MOVE:
		return _MOVE_LABEL
	if not _BINDINGS.has(action):
		return _UNKNOWN
	return OS.get_keycode_string(_BINDINGS[action])
