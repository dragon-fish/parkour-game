class_name InputNames
extends RefCounted

# What a key is CALLED, for anything that has to say so on screen.
#
# TUTORIAL COPY MUST NAME KEYS THROUGH HERE, NEVER AS LITERALS. The names come
# from InputBindings.current(), the same table KeyboardInputSource polls, so a
# prompt always names what the player bound -- not what this project shipped.

const MOVE := &"move"
const JUMP := &"jump"
const CROUCH := &"crouch"
const WALK := &"walk"
const TURN := &"turn"
const MELEE := &"melee"
const TOGGLE_VIEW := &"toggle_view"

## Movement is four actions, named together in this order.
const _MOVE_ACTIONS: Array[String] = [
	InputBindings.MOVE_FORWARD, InputBindings.MOVE_LEFT,
	InputBindings.MOVE_BACK, InputBindings.MOVE_RIGHT,
]

## Shown when copy asks for an action that does not exist. DELIBERATELY UGLY:
## a missing binding should be visible on screen during the first playtest,
## not read as a plausible key.
const _UNKNOWN := "???"

## Shown for an action the player left with no binding at all.
const _UNBOUND := "未绑定"

static func label(action: StringName) -> String:
	var bindings := InputBindings.current()
	if action == MOVE:
		return _move_label(bindings)
	if not bindings.has(String(action)):
		return _UNKNOWN
	return _first_label(bindings, String(action))

## The first bound slot's name: what the player reaches for first.
static func _first_label(bindings: Dictionary, action: String) -> String:
	for binding in bindings[action]:
		var name := InputBindings.binding_label(binding)
		if not name.is_empty():
			return name
	return _UNBOUND

## "WASD" when every direction is a single character, as the defaults are;
## spelled out with separators otherwise, since "Up" next to "Left" run
## together reads as one word.
static func _move_label(bindings: Dictionary) -> String:
	var names: Array[String] = []
	var all_single := true
	for action in _MOVE_ACTIONS:
		var name := _first_label(bindings, action)
		names.append(name)
		if name.length() != 1:
			all_single = false
	return "".join(names) if all_single else "/".join(names)
