extends CanvasLayer

# Global pause menu -- every level gets this for free via the autoload,
# debug whiteboxes included (the spec's "自动加载意味着 debug_levels 白盒里也
# 免费获得暂停菜单"). Esc toggles pause; 设置 is a placeholder until Task 4
# wires the settings page; 回主菜单 targets Task 5's scene, guarded so it
# simply does nothing until that scene exists.
#
# No class_name: this script's only identity is the autoload singleton name
# "PauseUi" project.godot binds it to -- a class_name of the same name would
# collide with that global.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _backdrop: ColorRect
var _menu_list: MeMenuList

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	# The boot-time application point for the window/audio half of
	# SettingsStore (see settings_store.gd's own split-in-two comment); the
	# per-player camera half is applied in Player.setup() instead, once a
	# MovementConfig exists to write into.
	SettingsStore.apply_global(SettingsStore.load_settings())
	_build_ui()
	_set_shown(false)

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = MeTheme.BACKDROP
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_menu_list = MeMenuList.new()
	_menu_list.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(_menu_list)
	_menu_list.set_items(["继续", "设置", "回主菜单"])
	_menu_list.chosen.connect(_on_chosen)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != KEY_ESCAPE:
		return
	if _is_main_menu_scene():
		return
	toggle_pause()
	get_viewport().set_input_as_handled()

## Whether the current scene IS the main menu, where Esc must do nothing (the
## spec's "主菜单场景里 Esc 不响应"). `current_scene == null` reads as "not the
## main menu" here rather than as a reason to block toggling -- it is the
## state of every headless test (GUT never sets a main scene, confirmed via
## a probe), and both toggle_pause() and this Esc path are required to work
## with no scene loaded at all.
##
## Guards by node name rather than `is MainMenu`: that class_name only
## exists from Task 5 onward. Once it lands, this can switch to a real type
## check.
func _is_main_menu_scene() -> bool:
	var current := get_tree().current_scene
	return current != null and current.name == "MainMenu"

func toggle_pause() -> void:
	if get_tree().paused:
		_resume()
	else:
		_pause()

func _pause() -> void:
	get_tree().paused = true
	_set_shown(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume() -> void:
	get_tree().paused = false
	_set_shown(false)
	if _current_scene_wants_mouse_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Single source of truth for "is the pause menu on screen". CanvasLayer is
## NOT a CanvasItem, so this node's own `visible` (set above) never cascades
## to child Controls -- each child keeps whatever `visible` it was last set
## to, forever, regardless of this layer's flag. Without this, MeMenuList's
## own `visible` stayed true permanently (nothing ever touched it), so its
## is_visible_in_tree()/visible input guard never actually gated anything --
## found in review: Up/Down/Enter kept reaching MeMenuList._unhandled_input,
## and it kept consuming them, even while the game was running unpaused with
## the menu never shown. Flips both the layer flag (for rendering) and the
## actual UI subtree's `visible` (for every script-side visibility check,
## MeMenuList's guard included).
func _set_shown(on: bool) -> void:
	visible = on
	_backdrop.visible = on
	_menu_list.visible = on

## Duck-typed against Arena.capture_mouse (scripts/level/arena.gd) -- a level
## that does not export the property, or no current scene at all, gets the
## capturing default every existing level already wants.
func _current_scene_wants_mouse_capture() -> bool:
	var current := get_tree().current_scene
	if current == null:
		return true
	if "capture_mouse" in current:
		return bool(current.capture_mouse)
	return true

func _on_chosen(index: int) -> void:
	match index:
		0:
			_resume()
		1:
			# Placeholder: Task 4 wires the settings page as a sub-page push.
			pass
		2:
			_go_to_main_menu()

func _go_to_main_menu() -> void:
	if not ResourceLoader.exists(MAIN_MENU_SCENE):
		return
	get_tree().paused = false
	_set_shown(false)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
