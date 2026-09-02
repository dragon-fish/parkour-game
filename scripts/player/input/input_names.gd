class_name InputNames
extends RefCounted

# What a key is CALLED, for anything that has to say so on screen.
#
# TUTORIAL COPY MUST NAME KEYS THROUGH HERE, NEVER AS LITERALS. Rebinding is
# not built yet -- KeyboardInputSource reads fixed physical keycodes and says
# so in its own header -- but copy written with "Shift" spelled into it will
# keep telling a player to press Shift after he has moved crouch to C, and
# finding every such line later means a full-text search that will miss one.
# Going through this table costs nothing today and makes that search
# unnecessary.
#
# When rebinding lands, only _BINDINGS changes.

const MOVE := &"move"
const JUMP := &"jump"
const CROUCH := &"crouch"
const WALK := &"walk"
const TURN := &"turn"

## The keys KeyboardInputSource actually polls. DO NOT let these drift from
## it -- a tutorial that names a key the game does not listen to is worse than
## one that names none.
const _BINDINGS: Dictionary = {
	JUMP: KEY_SPACE,
	CROUCH: KEY_SHIFT,
	WALK: KEY_CTRL,
	TURN: KEY_Q,
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
