extends CanvasLayer

# Global pause menu -- every level gets this for free via the autoload,
# debug whiteboxes included: autoloading means even a debug_levels
# whitebox gets a pause menu for free. Esc toggles pause, or backs out of
# the settings page when that is what is currently shown; the Settings
# choice pushes MeSettingsMenu in place of the menu list; the Back to Main
# Menu choice targets the main menu scene, guarded so it simply does
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
## Shared corner/footer pieces that carry no other state of their own --
## corner metadata labels and the footer key-hint. Built once in _build_ui(), then
## only ever have their `visible` flipped by _set_shown() alongside every
## other child on this layer (see that method's own comment for why a plain
## CanvasLayer needs this at all).
var _corner_labels: Array[Label] = []
var _footer: Label
## The shared ME retention dialog (MeTheme.confirm_dialog), built on first
## Quit press. Hidden alongside everything else by _set_shown(false).
var _quit_confirm: Control
## Whether the settings page (rather than the menu list) is the currently
## shown sub-page. Reset to false whenever the whole layer hides, so a fresh
## pause always opens back on the list -- see _set_shown().
var _showing_settings: bool = false

## Set by go_to_main_menu(), cleared by a call_deferred() queued right after
## the scene-change request itself. Guards a same-frame race:
## change_scene_to_file() is deferred -- for at least the rest of this frame
## get_tree().current_scene is still the OLD scene while the new one is only
## queued. Any toggle_pause() that lands in that gap (e.g. a second input
## event queued behind the one that fired Back to Main Menu) would otherwise re-pause a
## scene that is about to be torn down, or resume into a half-swapped tree --
## see toggle_pause() below.
##
## A DEFERRED CLEAR, NOT AN "IS IT THE MAIN MENU YET" CHECK. DO NOT clear
## this flag by having toggle_pause() observe _is_main_menu_scene() ==
## true: if the player leaves the main menu again (e.g. pressing Start)
## without ever triggering Esc/toggle_pause() WHILE the main menu was
## current, that check never fires, and the flag permanently no-ops every
## future toggle_pause() call, in every level, for the rest of the run.
## call_deferred() queues behind change_scene_to_file()'s own deferred work
## in the same message queue, so by the time this runs the swap has already
## happened -- and it fires exactly once, on a fixed one-frame schedule,
## with no dependency on what the player does afterward.
## The pause menu's rows, in order. Named fields rather than a positional
## array because this table will grow more of them; see
## .claude/skills/naming-config-fields.
##   label    String -- what the row says
##   handler  StringName -- the method on this node the row runs
const _ENTRIES := [
	{label = "继续游戏", handler = &"_resume"},
	{label = "上一检查点", handler = &"_respawn_at_checkpoint"},
	{label = "重新开始", handler = &"_restart_from_spawn"},
	{label = "设置", handler = &"_show_settings"},
	{label = "回主菜单", handler = &"go_to_main_menu"},
	{label = "退出游戏", handler = &"_show_quit_confirm"},
]

## The rows currently on screen, in the order MeMenuList was handed them.
##
## DISPATCH IS BY IDENTITY, NOT BY POSITION. MeMenuList reports an index into
## the labels it was given and nothing else, so leaving a row out used to
## renumber every handler below it with no error anywhere: 退出游戏 moved up
## onto 回主菜单's number and quit the game.
var _entries: Array[Dictionary] = []

var _pending_scene_change: bool = false
## The loading transition's white sheet -- lives here because this autoload
## survives the scene switch; MainMenu hands over at full white and the
## lift happens in the freshly-loaded level.
var _white: ColorRect

## Seam for go_to_main_menu(): swappable so a test can observe "Back to
## Main Menu was requested" without a real change_scene_to_file() replacing
## the scene tree out from under GUT's own runner mid-suite. Same shape as
## MainMenu's own
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
	# ABOVE ScreenEffects, which sits at 100 so a death blackout can cover the
	# crosshair and the HUD. The pause menu is the one thing that must be
	# readable through anything the body is currently suffering: at 10 it was
	# underneath, and pausing part-way into a blur or a fade left a menu
	# nobody could read. DO NOT lower this below ScreenEffects to fix a
	# layering problem elsewhere -- raise the other thing.
	layer = 200
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

	_menu_list = MeMenuList.new()
	# The main menu's full-height red column, same geometry -- the red runs
	# top to bottom, with the same breathing gap off the right edge. See
	# MainMenu._build_menu_list().
	_menu_list.custom_minimum_size = Vector2(420.0, 0.0)
	_menu_list.anchor_left = 1.0
	_menu_list.anchor_right = 1.0
	_menu_list.anchor_top = 0.0
	_menu_list.anchor_bottom = 1.0
	_menu_list.offset_left = -480.0
	_menu_list.offset_right = -60.0
	_menu_list.offset_top = 0.0
	_menu_list.offset_bottom = 0.0
	add_child(_menu_list)
	_refresh_entries()
	_menu_list.chosen.connect(_on_chosen)

	_settings_menu = MeSettingsMenu.new()
	add_child(_settings_menu)
	_settings_menu.closed.connect(_on_settings_closed)

	_build_corner_metadata()
	_build_footer()

## Corner metadata on the pause menu: the same language as the main menu
## (scripts/ui/main_menu.gd's own _build_corner_metadata()), built through
## the shared MeTheme.corner_label() helper so neither screen carries its
## own copy of the label shape. Pause has no version string of its own for
## the fourth corner the way the main menu does, so all four stay a plain
## "+".
func _build_corner_metadata() -> void:
	_corner_labels.append(MeTheme.corner_label("+", 0.0, 0.0, Vector2(20.0, 16.0)))
	_corner_labels.append(MeTheme.corner_label("+", 1.0, 0.0, Vector2(-20.0, 16.0), true))
	_corner_labels.append(MeTheme.corner_label("+", 0.0, 1.0, Vector2(20.0, -32.0)))
	_corner_labels.append(MeTheme.corner_label("+", 1.0, 1.0, Vector2(-20.0, -32.0), true))
	for label in _corner_labels:
		add_child(label)

## Pause's own truth, not the main menu's footer text: Esc resumes here,
## there is no Start to confirm into.
func _build_footer() -> void:
	_footer = MeTheme.footer_label("Esc 继续 · Enter 确认")
	add_child(_footer)

## The cover swallows input for every scene under it. Keyed on the sheet's
## own `visible` rather than a flag of its own: the two can then never fall
## out of sync, and there is no reset to forget -- a stuck flag here would
## kill input for the rest of the run.
##
## Runs in _input, not _unhandled_input, because that is what gets ahead of
## the scene's own handlers: the current scene enters the tree after this
## autoload, so it is offered _input first, but nothing reaches
## _unhandled_input once the event is marked handled.
##
## DOES NOT cover Player. KeyboardInputSource polls Input.is_key_pressed()
## rather than reading events, and no amount of set_input_as_handled()
## reaches a poll -- player.lock_input() in run_white_transition() is still
## what holds the player still under the white.
func _input(_event: InputEvent) -> void:
	if _white != null and _white.visible:
		get_viewport().set_input_as_handled()

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

## Whether the current scene IS the main menu, where Esc must do nothing --
## the main menu scene does not respond to Esc. `current_scene == null`
## reads as "not the
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
## visibility check, MeMenuList's guard included) -- the shared corner/
## (paper noise, corner labels, footer) included, since the same
## non-cascading CanvasLayer gotcha applies to them exactly as much as it did
## to MeMenuList -- choosing between the list and the settings page via
## _showing_settings.
## Rebuilds the row list from _ENTRIES. Rebuilt rather than diffed: MeMenuList
## resets its selection on set_items(), and a pause that opens on the top row
## is what a fresh pause should do anyway.
func _refresh_entries() -> void:
	_entries = []
	var labels: Array[String] = []
	for entry in _ENTRIES:
		_entries.append(entry)
		labels.append(entry.label)
	_menu_list.set_items(labels)

func _set_shown(on: bool) -> void:
	visible = on
	_backdrop.visible = on
	_paper_noise.visible = on
	_footer.visible = on
	for label in _corner_labels:
		label.visible = on
	if not on:
		_showing_settings = false
		if _quit_confirm != null:
			_quit_confirm.visible = false
	_menu_list.visible = on and not _showing_settings
	_settings_menu.visible = on and _showing_settings

## Duck-typed against Arena.capture_mouse (scripts/level/arena.gd) -- a level
## that does not export the property, or no current scene at all, gets the
## capturing default every existing level already wants. MainMenu is special-
## cased to false ahead of that duck-typing (it has no capture_mouse property
## to find anyway, so this is belt-and-suspenders): a "rescue-resume" --
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
	if index < 0 or index >= _entries.size():
		return
	call(_entries[index].handler)

## The "last checkpoint" menu choice: the R-tap action, from the menu --
## resume first (the pause menu has no business surviving its own choice),
## then the level's own respawn, which honours the last-touched checkpoint.
## Duck-typed on Arena so a scene without one (or no scene, in tests) makes
## this a no-op.
##
## THE SAME CALL THE R KEY MAKES. It used to reach past it to reset_player(),
## which teleported the body with no transition at all -- so the identical
## action looked like a glitch from the menu and like a deliberate reset from
## the key.
func _respawn_at_checkpoint() -> void:
	var arena := get_tree().current_scene as Arena
	if arena == null:
		return
	_resume()
	arena.respawn_at_checkpoint()

## The "restart" menu choice: the R-hold action -- forget the checkpoint
## and restart from the level's own spawn, under Arena's white cover.
func _restart_from_spawn() -> void:
	var arena := get_tree().current_scene as Arena
	if arena == null:
		return
	_resume()
	arena.restart_from_spawn()

func _show_quit_confirm() -> void:
	if _quit_confirm == null:
		_quit_confirm = MeTheme.confirm_dialog(
			"就这么走了吗？外面还有屋顶没跑完。", "再跑一会儿", "退出游戏",
			func() -> void: get_tree().quit())
		add_child(_quit_confirm)
	_quit_confirm.visible = true

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

## Both the Save Settings and Cancel buttons route here via
## MeSettingsMenu.closed -- pop back to the menu list. Also the
## Esc-while-in-settings path's eventual destination
## (via _unhandled_input -> MeSettingsMenu._on_cancel_pressed -> closed).
## Re-derives from this layer's current `visible` rather than assuming true,
## since _set_shown() is the only place allowed to decide sub-page visibility.
func _on_settings_closed() -> void:
	_showing_settings = false
	_set_shown(visible)

## Sends the game back to the front door. PUBLIC because the settings page's
## 重玩新手教程 row needs this exact route from either of its two hosts.
func go_to_main_menu() -> void:
	if not ResourceLoader.exists(MAIN_MENU_SCENE):
		return
	_set_shown(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pending_scene_change = true
	# Normal transitions are WHITE (the transition-colour convention).
	# Headless keeps the bare seam for the tests (embedded renders fine and
	# gets the show).
	if DisplayServer.get_name() == "headless":
		_change_scene.call(MAIN_MENU_SCENE)
		call_deferred("_clear_pending_scene_change")
		return
	run_white_transition(load(MAIN_MENU_SCENE), 0.4)
	call_deferred("_clear_pending_scene_change")

func _clear_pending_scene_change() -> void:
	_pending_scene_change = false

## The loading handoff: fade to pure white over `fade_in`, switch to
## `packed` UNDER the white (the instantiate hitch hides there), hold a few
## frames for the new scene's first paint, then lift. Runs on this autoload
## so the cover outlives the caller.
func run_white_transition(packed: PackedScene, fade_in: float = 0.7) -> void:
	# The sheet lives on THIS CanvasLayer, and _set_shown(false) keeps the
	# whole layer invisible while unpaused -- so the layer itself must wake
	# for the transition (the pause UI's children keep their own hidden
	# flags and stay out of sight).
	visible = true
	_white.visible = true
	move_child(_white, get_child_count() - 1)
	var tween := create_tween()
	tween.tween_property(_white, "modulate:a", 1.0, fade_in) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_pending_scene_change = true
	var swap_started := Time.get_ticks_msec()
	get_tree().change_scene_to_packed(packed)
	for i in 6:
		await get_tree().process_frame
	_pending_scene_change = false
	print("[load] scene swap + every _ready(): %d ms" % (Time.get_ticks_msec() - swap_started))

	# THE ONE PART NO HEADLESS MEASUREMENT CAN SEE. Godot compiles a material
	# pipeline the first time it is actually DRAWN, so the first few frames of
	# a new level can each stall on shaders that no loader and no _ready()
	# timing knows about -- a DIFFERENT cost from the 2.25 s deep-copy Arena's
	# own load logging found (see arena.gd's _ready()). A frame over ~50 ms
	# here is a pipeline being built, not a slow scene.
	var frame_started := Time.get_ticks_msec()
	var worst := 0
	var stalls := 0
	for i in 20:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var frame := now - frame_started
		frame_started = now
		if frame > 50:
			stalls += 1
			print("[load]   first-draw frame %2d stalled %d ms" % [i, frame])
		worst = maxi(worst, frame)
	print("[load] first 20 frames drawn: worst %d ms, %d over 50 ms" % [worst, stalls])

	# THE LEVEL IS ALREADY LIVE UNDER THE SHEET. change_scene_to_packed has
	# returned, every _ready() has run and the player is standing in the world
	# taking input -- while the screen is still solid white. DO NOT allow
	# camera control or movement during the transition: the player could wave
	# the mouse around and run off before loading has actually finished.
	# lock_input() covers BOTH: Player feeds a blank MoveInput to the moves
	# AND to camera_rig.apply_look, so the mouse is dead too.
	var player := _player_in_the_new_scene()
	if player != null:
		player.lock_input()
	var lift := create_tween()
	lift.tween_property(_white, "modulate:a", 0.0, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await lift.finished
	if is_instance_valid(player):
		player.unlock_input()
	print("[load] white lifted, controls live")
	_white.visible = false
	# Back to the resting state: the layer only shows when paused.
	if not get_tree().paused:
		visible = false


## The Player of whichever scene is current, or null before one exists.
## Searched rather than held: this autoload outlives every scene, so any
## reference it kept would be to a level that has already been freed.
func _player_in_the_new_scene() -> Player:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	if scene is Player:
		return scene
	for node in scene.find_children("*", "Player", true, false):
		return node as Player
	return null
