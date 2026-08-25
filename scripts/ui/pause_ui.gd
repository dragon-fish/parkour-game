extends CanvasLayer

# Global pause menu -- every level gets this for free via the autoload,
# debug whiteboxes included (the spec's "自动加载意味着 debug_levels 白盒里也
# 免费获得暂停菜单"). Esc toggles pause, or backs out of the settings page
# when that is what is currently shown; 设置 pushes MeSettingsMenu in place of
# the menu list; 回主菜单 targets Task 5's scene, guarded so it simply does
# nothing until that scene exists.
#
# No class_name: this script's only identity is the autoload singleton name
# "PauseUi" project.godot binds it to -- a class_name of the same name would
# collide with that global.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _backdrop: ColorRect
var _paper_noise: ColorRect
var _menu_list: MeMenuList
var _settings_menu: MeSettingsMenu
## 现代化改良五件套 pieces that carry no other state of their own -- corner
## metadata labels and the footer key-hint. Built once in _build_ui(), then
## only ever have their `visible` flipped by _set_shown() alongside every
## other child on this layer (see that method's own comment for why a plain
## CanvasLayer needs this at all).
var _corner_labels: Array[Label] = []
var _footer: Label
## Whether the settings page (rather than the menu list) is the currently
## shown sub-page. Reset to false whenever the whole layer hides, so a fresh
## pause always opens back on the list -- see _set_shown().
var _showing_settings: bool = false

## Set by _go_to_main_menu(), cleared by a call_deferred() queued right after
## the scene-change request itself. Guards a same-frame race:
## change_scene_to_file() is deferred -- for at least the rest of this frame
## get_tree().current_scene is still the OLD scene while the new one is only
## queued. Any toggle_pause() that lands in that gap (e.g. a second input
## event queued behind the one that fired 回主菜单) would otherwise re-pause a
## scene that is about to be torn down, or resume into a half-swapped tree --
## see toggle_pause() below.
##
## A DEFERRED CLEAR, NOT AN "IS IT THE MAIN MENU YET" CHECK: an earlier
## version of this cleared the flag only once toggle_pause() itself observed
## _is_main_menu_scene() == true. That went stuck forever the moment the
## player left the main menu again (e.g. pressing 开始) without ever
## triggering Esc/toggle_pause() WHILE the main menu was current -- the flag
## then permanently no-op'd every future toggle_pause() call, in every level,
## for the rest of the run. call_deferred() queues behind
## change_scene_to_file()'s own deferred work in the same message queue, so
## by the time this runs the swap has already happened -- and it fires
## exactly once, on a fixed one-frame schedule, with no dependency on what
## the player does afterward.
var _pending_scene_change: bool = false
## The loading transition's white sheet -- lives here because this autoload
## survives the scene switch; MainMenu hands over at full white and the
## lift happens in the freshly-loaded level.
var _white: ColorRect

## Seam for _go_to_main_menu(): swappable so a test can observe "回主菜单 was
## requested" without a real change_scene_to_file() replacing the scene tree
## out from under GUT's own runner mid-suite. Same shape as MainMenu's own
## _change_scene (scripts/ui/main_menu.gd). Defaults to the real thing.
var _change_scene: Callable = Callable(self, "_real_change_scene")

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	_white = ColorRect.new()
	_white.color = Color.WHITE
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.modulate.a = 0.0
	_white.visible = false
	add_child(_white)
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

	_paper_noise = MeTheme.paper_noise_layer()
	add_child(_paper_noise)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_menu_list = MeMenuList.new()
	_menu_list.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(_menu_list)
	_menu_list.set_items(["继续", "设置", "回主菜单"])
	_menu_list.chosen.connect(_on_chosen)

	_settings_menu = MeSettingsMenu.new()
	add_child(_settings_menu)
	_settings_menu.closed.connect(_on_settings_closed)

	_build_corner_metadata()
	_build_footer()

## 现代化五件套 on the pause menu: the same corner-metadata language as the
## main menu (scripts/ui/main_menu.gd's own _build_corner_metadata()), built
## through the shared MeTheme.corner_label() helper so neither screen carries
## its own copy of the label shape. Pause has no version string of its own
## for the fourth corner the way the main menu does, so all four stay a
## plain "+".
func _build_corner_metadata() -> void:
	_corner_labels.append(MeTheme.corner_label("+", 0.0, 0.0, Vector2(20.0, 16.0)))
	_corner_labels.append(MeTheme.corner_label("+", 1.0, 0.0, Vector2(-20.0, 16.0), true))
	_corner_labels.append(MeTheme.corner_label("+", 0.0, 1.0, Vector2(20.0, -32.0)))
	_corner_labels.append(MeTheme.corner_label("+", 1.0, 1.0, Vector2(-20.0, -32.0), true))
	for label in _corner_labels:
		add_child(label)

## Pause's own truth, not the main menu's footer text: Esc resumes here,
## there is no 开始 to confirm into.
func _build_footer() -> void:
	_footer = MeTheme.footer_label("Esc 继续 · Enter 确认")
	add_child(_footer)

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
	# Deliberately checked here rather than left to relying on MeSettingsMenu
	# consuming the event first via child-before-parent input propagation --
	# this branch is the single, deterministic source of truth for what Esc
	# means, testable by calling _unhandled_input() directly exactly like the
	# toggle_pause() path below already is.
	if _showing_settings:
		_settings_menu._on_cancel_pressed()
		get_viewport().set_input_as_handled()
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
## Prefers the real `is MainMenu` type check, now that Task 5's class_name
## exists. Falls back to the node-name check this used before that class
## existed -- tolerant rather than strict, so a stand-in scene built for a
## test (a MainMenu instance that never went through main_menu.tscn, or any
## future scene that simply names its root "MainMenu") still reads as the
## main menu even without the exact class.
func _is_main_menu_scene() -> bool:
	var current := get_tree().current_scene
	if current == null:
		return false
	if current is MainMenu:
		return true
	return current.name == "MainMenu"

func toggle_pause() -> void:
	if _pending_scene_change:
		# Mid-transition to the main menu -- a no-op rather than pausing/
		# resuming a scene that is about to be replaced out from under it.
		return
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

## Single source of truth for "is the pause menu on screen" AND "which
## sub-page is showing" -- _show_settings()/_on_settings_closed() below only
## flip _showing_settings and re-call this with the layer's current `visible`
## state; they never write _menu_list.visible/_settings_menu.visible
## themselves. CanvasLayer is NOT a CanvasItem, so this node's own `visible`
## (set above) never cascades to child Controls -- each child keeps whatever
## `visible` it was last set to, forever, regardless of this layer's flag.
## Without this, MeMenuList's own `visible` stayed true permanently (nothing
## ever touched it), so its is_visible_in_tree()/visible input guard never
## actually gated anything -- found in review: Up/Down/Enter kept reaching
## MeMenuList._unhandled_input, and it kept consuming them, even while the
## game was running unpaused with the menu never shown. Flips the layer flag
## (for rendering) and every child's `visible` (for every script-side
## visibility check, MeMenuList's guard included) -- the 现代化五件套 pieces
## (paper noise, corner labels, footer) included, since the same
## non-cascading CanvasLayer gotcha applies to them exactly as much as it did
## to MeMenuList -- choosing between the list and the settings page via
## _showing_settings.
func _set_shown(on: bool) -> void:
	visible = on
	_backdrop.visible = on
	_paper_noise.visible = on
	_footer.visible = on
	for label in _corner_labels:
		label.visible = on
	if not on:
		_showing_settings = false
	_menu_list.visible = on and not _showing_settings
	_settings_menu.visible = on and _showing_settings

## Duck-typed against Arena.capture_mouse (scripts/level/arena.gd) -- a level
## that does not export the property, or no current scene at all, gets the
## capturing default every existing level already wants. MainMenu is special-
## cased to false ahead of that duck-typing (it has no capture_mouse property
## to find anyway, so this is belt-and-suspenders): a "rescue-继续" resume --
## Esc pressed while the current scene happens to be the main menu, e.g.
## during the _pending_scene_change window above -- must never grab the
## cursor away from a screen whose own buttons need it.
func _current_scene_wants_mouse_capture() -> bool:
	if _is_main_menu_scene():
		return false
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
			_show_settings()
		2:
			_go_to_main_menu()

## Pushes the settings page in place of the menu list. reload() re-reads
## SettingsStore fresh, so this always starts from what is actually on disk
## rather than whatever a previous, already-cancelled visit left in memory.
## Delegates the actual visibility flip to _set_shown() -- see its doc
## comment -- rather than touching _menu_list.visible/_settings_menu.visible
## here directly.
func _show_settings() -> void:
	_showing_settings = true
	_settings_menu.reload()
	_set_shown(visible)

## Both 保存设置 and 取消 route here via MeSettingsMenu.closed -- pop back to
## the menu list. Also the Esc-while-in-settings path's eventual destination
## (via _unhandled_input -> MeSettingsMenu._on_cancel_pressed -> closed).
## Re-derives from this layer's current `visible` rather than assuming true,
## since _set_shown() is the only place allowed to decide sub-page visibility.
func _on_settings_closed() -> void:
	_showing_settings = false
	_set_shown(visible)

func _go_to_main_menu() -> void:
	if not ResourceLoader.exists(MAIN_MENU_SCENE):
		return
	_set_shown(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pending_scene_change = true
	# ✅ The owner's convention: normal transitions are WHITE. Headless keeps
	# the bare seam for the tests (embedded renders fine and gets the show).
	if DisplayServer.get_name() == "headless":
		_change_scene.call(MAIN_MENU_SCENE)
		call_deferred("_clear_pending_scene_change")
		return
	run_white_transition(load(MAIN_MENU_SCENE), 0.4)
	call_deferred("_clear_pending_scene_change")

func _clear_pending_scene_change() -> void:
	_pending_scene_change = false

## The loading handoff (✅ the owner's fake-load choreography): fade to pure
## white over `fade_in`, switch to `packed` UNDER the white (the instantiate
## hitch hides there), hold a few frames for the new scene's first paint,
## then lift. Runs on this autoload so the cover outlives the caller.
func run_white_transition(packed: PackedScene, fade_in: float = 0.7) -> void:
	_white.visible = true
	move_child(_white, get_child_count() - 1)
	var tween := create_tween()
	tween.tween_property(_white, "modulate:a", 1.0, fade_in) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_pending_scene_change = true
	get_tree().change_scene_to_packed(packed)
	for i in 6:
		await get_tree().process_frame
	_pending_scene_change = false
	var lift := create_tween()
	lift.tween_property(_white, "modulate:a", 0.0, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await lift.finished
	_white.visible = false
