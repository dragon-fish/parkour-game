class_name InputBindings
extends RefCounted

# Which physical input each bindable action listens to. Static and stateless
# apart from the table in use, same shape as SettingsStore -- never
# instantiated.
#
# THE SINGLE SOURCE OF TRUTH for bindings. KeyboardInputSource polls through
# current(), Player matches its camera events through matches(), InputNames
# names keys on screen through label_for(). The table is persisted as one key
# of the SettingsStore blob (`bindings`), so it is saved, cancelled and reset
# with the rest of the settings page; SettingsStore.apply_global() is what
# puts a saved table into use.
#
# Debug and system keys (Esc, Tab, the F-keys, R, K, T, PgUp/PgDn) are NOT
# actions here and cannot be bound: see RESERVED_KEYS. Cutscene skip is not an
# action either -- the original keeps it on the space bar whatever jump is
# bound to (TdPlayerInput.SetBind appends SkipCutscene to SpaceBar and only
# SpaceBar), and KismetRunner.SKIP_KEY does the same.

const MOVE_FORWARD := "move_forward"
const MOVE_BACK := "move_back"
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const JUMP := "jump"
const CROUCH := "crouch"
const WALK := "walk"
const TURN := "turn"
const MELEE := "melee"
const TOGGLE_VIEW := "toggle_view"
const ZOOM_IN := "zoom_in"
const ZOOM_OUT := "zoom_out"
const FRAME_CAMERA := "frame_camera"

## Bindings per action: a primary and a secondary.
const SLOTS := 2

## A binding is a Dictionary with a `kind` and one field for that kind:
##   {kind = "key", code = <physical Key>}       a key by POSITION, so a
##                                               layout change never moves it
##   {kind = "mouse", button = <MouseButton>}   a mouse button, the wheel
##                                               directions included
## An empty slot is the empty Dictionary {}.
const KIND_KEY := "key"
const KIND_MOUSE := "mouse"

## The bindable actions, in the order the settings page lists them.
##   id        the action's name everywhere in code
##   label     what the settings page and the conflict dialog call it
##   desc      the settings page's description for the row
##   defaults  up to SLOTS bindings; MUST equal the keys this project read
##             before bindings existed, so a fresh install plays the same
const ACTIONS: Array[Dictionary] = [
	{id = MOVE_FORWARD, label = "前进", desc = "向前移动。",
		defaults = [{kind = KIND_KEY, code = KEY_W}]},
	{id = MOVE_BACK, label = "后退", desc = "向后移动。",
		defaults = [{kind = KIND_KEY, code = KEY_S}]},
	{id = MOVE_LEFT, label = "向左", desc = "向左平移。",
		defaults = [{kind = KIND_KEY, code = KEY_A}]},
	{id = MOVE_RIGHT, label = "向右", desc = "向右平移。",
		defaults = [{kind = KIND_KEY, code = KEY_D}]},
	{id = JUMP, label = "跳跃", desc = "跳跃，以及一切向上的动作。可以绑定到滚轮：每滚动一格算按下一次。",
		defaults = [{kind = KIND_KEY, code = KEY_SPACE}]},
	{id = CROUCH, label = "蹲下", desc = "蹲下、滑铲，以及一切向下的动作。",
		defaults = [{kind = KIND_KEY, code = KEY_SHIFT}]},
	{id = WALK, label = "慢走", desc = "按住时放慢移动速度。",
		defaults = [{kind = KIND_KEY, code = KEY_CTRL}]},
	{id = TURN, label = "转身", desc = "快速转身 180 度。",
		defaults = [{kind = KIND_KEY, code = KEY_Q}]},
	{id = MELEE, label = "攻击", desc = "近身攻击。",
		defaults = [{kind = KIND_MOUSE, button = MOUSE_BUTTON_LEFT}]},
	{id = TOGGLE_VIEW, label = "切换视角", desc = "在第一人称与第三人称之间切换。",
		defaults = [{kind = KIND_KEY, code = KEY_V}]},
	{id = ZOOM_IN, label = "镜头拉近", desc = "第三人称下拉近镜头。第一人称下不起作用。",
		defaults = [{kind = KIND_MOUSE, button = MOUSE_BUTTON_WHEEL_UP}]},
	{id = ZOOM_OUT, label = "镜头拉远", desc = "第三人称下拉远镜头。第一人称下不起作用。",
		defaults = [{kind = KIND_MOUSE, button = MOUSE_BUTTON_WHEEL_DOWN}]},
	{id = FRAME_CAMERA, label = "调整镜头", desc = "第三人称下按住并移动鼠标调整镜头构图，单击切换左右肩。",
		defaults = [{kind = KIND_MOUSE, button = MOUSE_BUTTON_MIDDLE}]},
]

## Keys that belong to the menus and the debug tools. DO NOT let a binding take
## one: the key would then do both things at once (R would jump AND respawn).
## Esc, Delete and Backspace are also the capture's own controls.
const RESERVED_KEYS: Array[int] = [
	KEY_ESCAPE, KEY_DELETE, KEY_BACKSPACE, KEY_TAB,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6,
	KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_R, KEY_K, KEY_T, KEY_PAGEUP, KEY_PAGEDOWN,
]

## The wheel's directions. A notch is an instantaneous press with no held
## state to poll: see KeyboardInputSource.accumulate_button().
const WHEEL_BUTTONS: Array[int] = [
	MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
]

const _MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "鼠标左键",
	MOUSE_BUTTON_RIGHT: "鼠标右键",
	MOUSE_BUTTON_MIDDLE: "鼠标中键",
	MOUSE_BUTTON_WHEEL_UP: "滚轮上",
	MOUSE_BUTTON_WHEEL_DOWN: "滚轮下",
	MOUSE_BUTTON_WHEEL_LEFT: "滚轮左",
	MOUSE_BUTTON_WHEEL_RIGHT: "滚轮右",
	MOUSE_BUTTON_XBUTTON1: "鼠标侧键 1",
	MOUSE_BUTTON_XBUTTON2: "鼠标侧键 2",
}

## The table in use. Empty until first asked for, then the defaults until
## SettingsStore.apply_global() puts the saved one in.
static var _current: Dictionary = {}


static func key(code: Key) -> Dictionary:
	return {kind = KIND_KEY, code = code}


static func mouse(button: MouseButton) -> Dictionary:
	return {kind = KIND_MOUSE, button = button}


## action id -> Array of SLOTS bindings, every action at its shipped default.
static func defaults() -> Dictionary:
	var out := {}
	for action in ACTIONS:
		var slots: Array = []
		for binding in action.defaults:
			slots.append((binding as Dictionary).duplicate())
		while slots.size() < SLOTS:
			slots.append({})
		out[action.id] = slots
	return out


## A table read from disk, made safe to use: every action present with exactly
## SLOTS slots, anything malformed emptied. An action missing from the file
## (one added after it was written) takes its default; an action the file has
## with both slots empty stays unbound -- the player cleared it.
static func sanitized(raw: Variant) -> Dictionary:
	var out := defaults()
	if not (raw is Dictionary):
		return out
	for action_id in out:
		var saved: Variant = (raw as Dictionary).get(action_id)
		if not (saved is Array):
			continue
		var slots: Array = []
		for binding in saved:
			if slots.size() >= SLOTS:
				break
			slots.append(binding.duplicate() if is_valid(binding) else {})
		while slots.size() < SLOTS:
			slots.append({})
		out[action_id] = slots
	return out


static func is_valid(binding: Variant) -> bool:
	if not (binding is Dictionary):
		return false
	var b: Dictionary = binding
	if b.get("kind") == KIND_KEY:
		return b.get("code") is int and int(b.code) != KEY_NONE
	if b.get("kind") == KIND_MOUSE:
		return b.get("button") is int and int(b.button) != MOUSE_BUTTON_NONE
	return false


static func current() -> Dictionary:
	if _current.is_empty():
		_current = defaults()
	return _current


## Puts a table into use. Copied, so a settings page editing its own working
## copy never changes what the game reads before 保存设置.
static func use(bindings: Dictionary) -> void:
	_current = sanitized(bindings)


static func same(a: Dictionary, b: Dictionary) -> bool:
	if not is_valid(a) or not is_valid(b) or a.kind != b.kind:
		return false
	if a.kind == KIND_KEY:
		return int(a.code) == int(b.code)
	return int(a.button) == int(b.button)


static func is_wheel(binding: Dictionary) -> bool:
	return is_valid(binding) and binding.kind == KIND_MOUSE \
		and int(binding.button) in WHEEL_BUTTONS


static func is_reserved(binding: Dictionary) -> bool:
	return is_valid(binding) and binding.kind == KIND_KEY \
		and int(binding.code) in RESERVED_KEYS


## The binding an event is made of, whether it is a press or a release; {} for
## an event no binding can be (motion, a key with no physical code).
static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code := (event as InputEventKey).physical_keycode
		return key(code) if code != KEY_NONE else {}
	if event is InputEventMouseButton:
		return mouse((event as InputEventMouseButton).button_index)
	return {}


## Whether `event` is one of `action`'s bindings, pressed or released.
static func matches(event: InputEvent, action: String, bindings: Dictionary = current()) -> bool:
	var binding := from_event(event)
	if binding.is_empty():
		return false
	for slot in bindings.get(action, []):
		if same(slot, binding):
			return true
	return false


## The action `binding` is bound to in `bindings`, or "" if none.
static func owner_of(bindings: Dictionary, binding: Dictionary) -> String:
	for action_id in bindings:
		for slot in bindings[action_id]:
			if same(slot, binding):
				return action_id
	return ""


static func action_label(action: String) -> String:
	for entry in ACTIONS:
		if entry.id == action:
			return entry.label
	return action


## What a binding is called on screen; "" for an empty slot.
static func binding_label(binding: Dictionary) -> String:
	if not is_valid(binding):
		return ""
	if binding.kind == KIND_KEY:
		return OS.get_keycode_string(int(binding.code))
	return _MOUSE_NAMES.get(int(binding.button), "鼠标按键 %d" % int(binding.button))
