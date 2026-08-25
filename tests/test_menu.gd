extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

# Minimal smoke tests for the ME theme factory (Task 1 of the menu feature).
# Structural only: MeTheme is a static, stateless factory, and the two
# gdshader resources have no visual output to assert on here -- later menu
# tasks exercise them in a real scene. What matters at this layer is that
# the factories hand back the right shapes and that both shaders actually
# compile (a ShaderMaterial with shader == null, or a Godot shader-compile
# error printed to stderr, is the failure mode this guards against).

func test_button_style_is_a_leaning_stylebox() -> void:
	var style := MeTheme.button_style(MeTheme.BRAND_RED)
	assert_not_null(style, "button_style returned nothing")
	assert_eq(style.bg_color, MeTheme.BRAND_RED, "button_style dropped the requested bg color")
	assert_true(style.skew.x < 0.0, "button_style is not leaning (skew.x >= 0)")

func test_wave_material_loads_its_shader() -> void:
	var material := MeTheme.wave_material(6.0)
	assert_not_null(material, "wave_material returned nothing")
	assert_not_null(material.shader, "wave_material's ShaderMaterial has no Shader resource")
	assert_eq(material.get_shader_parameter("amplitude_px"), 6.0, "amplitude_px was not applied")

func test_dot_grid_material_loads_its_shader() -> void:
	var material := MeTheme.dot_grid_material()
	assert_not_null(material, "dot_grid_material returned nothing")
	assert_not_null(material.shader, "dot_grid_material's ShaderMaterial has no Shader resource")


# ---------------------------------------------------------------------------
# SettingsStore (Task 2 of the menu feature): a pure-logic settings blob --
# defaults, load/save round-trip through user://settings.cfg, and applying
# the blob to a MovementConfig (camera fields) and to the engine (audio bus,
# window -- window is guarded off in headless and untestable here).
# ---------------------------------------------------------------------------

## Injected for the whole file's run rather than per-test: SettingsStore.path
## is a shared static, and pointing it at a throwaway file here means every
## load_settings()/save_settings() call anywhere in this suite -- including
## indirectly, through PauseUi._ready() and Player.setup() -- reads and
## writes user://settings_test.cfg instead of the author's real
## user://settings.cfg. Restored in after_all() so nothing outside this file
## ever sees the redirected path.
const _TEST_SETTINGS_PATH := "user://settings_test.cfg"
var _real_settings_path: String

func before_all() -> void:
	_real_settings_path = SettingsStore.path
	SettingsStore.path = _TEST_SETTINGS_PATH

func after_all() -> void:
	_delete_settings_file()
	SettingsStore.path = _real_settings_path

func before_each() -> void:
	_delete_settings_file()

func after_each() -> void:
	_delete_settings_file()
	# Unconditional pause/mouse-mode cleanup, run for EVERY test in this file
	# (not just the PauseUi ones below) so a failed assertion mid-test never
	# leaves the tree paused for every suite that runs after this one -- a
	# stuck get_tree().paused = true stalls ParkourTest.step()'s physics_frame
	# await across the whole rest of the process.
	#
	# _set_shown(false), not a plain `PauseUi.visible = false`: that only
	# flips the CanvasLayer's own flag, not the actual menu subtree's
	# `visible` -- see pause_ui.gd's _set_shown() for why that distinction
	# is exactly the bug this task's review round found.
	get_tree().paused = false
	PauseUi._set_shown(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Same reasoning as the two lines above, for the FIX 5 pending-scene-change
	# guard (test_go_to_main_menu_unpauses_before_requesting_the_scene_change
	# below): a stuck true would silently no-op every toggle_pause() in every
	# test that runs after it.
	PauseUi._pending_scene_change = false
	PauseUi._change_scene = Callable(PauseUi, "_real_change_scene")

func _delete_settings_file() -> void:
	if FileAccess.file_exists(SettingsStore.path):
		DirAccess.remove_absolute(SettingsStore.path)

func test_load_settings_with_no_file_returns_defaults() -> void:
	var loaded := SettingsStore.load_settings()
	assert_eq(loaded, SettingsStore.defaults(), "missing settings.cfg should load as defaults")

func test_save_then_load_round_trips_every_key() -> void:
	var saved := SettingsStore.defaults()
	saved.window_mode = "fullscreen"
	saved.window_size = Vector2i(1920, 1080)
	saved.sensitivity = 0.0035
	saved.fov = 100.0
	saved.volume_db = -6.0

	SettingsStore.save_settings(saved)
	var loaded := SettingsStore.load_settings()

	for key in saved:
		assert_eq(loaded[key], saved[key], "key '%s' did not round-trip" % key)

func test_apply_to_config_writes_camera_sensitivity_and_fov() -> void:
	var config := MovementConfig.new()
	var s := SettingsStore.defaults()
	s.sensitivity = 0.0099
	s.fov = 77.0

	SettingsStore.apply_to_config(s, config)

	assert_eq(config.camera.mouse_sensitivity, 0.0099, "apply_to_config did not write mouse_sensitivity")
	assert_eq(config.camera.fov_base, 77.0, "apply_to_config did not write fov_base")

func test_apply_global_sets_master_bus_volume_and_restores_it() -> void:
	var bus := AudioServer.get_bus_index("Master")
	var original_db := AudioServer.get_bus_volume_db(bus)

	var s := SettingsStore.defaults()
	s.volume_db = -12.0
	SettingsStore.apply_global(s)

	assert_eq(AudioServer.get_bus_volume_db(bus), -12.0, "apply_global did not set the Master bus volume")

	AudioServer.set_bus_volume_db(bus, original_db)


# ---------------------------------------------------------------------------
# PauseUi (Task 3 of the menu feature): the global pause autoload. Esc
# toggles get_tree().paused, either through the public toggle_pause() or by
# being fed straight into _unhandled_input; both leave the mouse mode
# consistent with the resulting pause state. after_each() above unpauses and
# resets mouse mode even on a failed assertion.
# ---------------------------------------------------------------------------

func test_toggle_pause_flips_paused_and_mouse_mode() -> void:
	assert_false(get_tree().paused, "test setup: tree was already paused")

	PauseUi.toggle_pause()
	assert_true(get_tree().paused, "toggle_pause did not pause the tree")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "pausing did not release the mouse")

	PauseUi.toggle_pause()
	assert_false(get_tree().paused, "second toggle_pause did not resume")

func test_esc_key_through_unhandled_input_flips_paused() -> void:
	assert_false(get_tree().paused, "test setup: tree was already paused")

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	esc.echo = false

	PauseUi._unhandled_input(esc)
	assert_true(get_tree().paused, "Esc through _unhandled_input did not pause")

	PauseUi._unhandled_input(esc)
	assert_false(get_tree().paused, "second Esc through _unhandled_input did not resume")

## Regression (review round 1): CanvasLayer is not a CanvasItem, so
## PauseUi's own `visible` never cascades to MeMenuList's `visible` -- a
## guard reading that plain property stayed true forever, meaning stray
## Up/Down/Enter in ordinary, unpaused play were silently being consumed by
## the (invisible, inactive) pause menu. Confirms the hidden list now goes
## quiet: no chosen signal, no selection movement, no pause-state change.
func test_hidden_menu_list_ignores_arrow_and_enter_keys() -> void:
	assert_false(get_tree().paused, "test setup: tree was already paused")
	var list: MeMenuList = PauseUi._menu_list
	assert_false(list.is_visible_in_tree(), "test setup: menu list should start hidden")

	# Array-boxed, not a plain bool: GDScript lambdas capture outer locals BY
	# VALUE, so `chosen_fired = true` inside the closure would silently only
	# ever mutate the closure's own copy -- verified with a throwaway probe
	# after this test first passed for the wrong reason (chosen_fired started
	# false and a no-op assignment left it looking "correctly" false). A
	# boxed array is captured by value too, but that value IS the reference
	# to the array object, so writing into slot 0 is visible outside.
	var chosen_fired := [false]
	var on_chosen := func(_i): chosen_fired[0] = true
	list.chosen.connect(on_chosen)
	var starting_index: int = list._selected_index

	var down := InputEventKey.new()
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	down.echo = false
	list._unhandled_input(down)

	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	enter.echo = false
	list._unhandled_input(enter)

	list.chosen.disconnect(on_chosen)

	assert_false(chosen_fired[0], "a hidden menu list must not fire chosen")
	assert_eq(list._selected_index, starting_index, "a hidden menu list must not move its selection")
	assert_false(get_tree().paused, "a hidden menu list's input must not touch pause state")

## The positive twin of the regression above: once PauseUi actually shows
## the list (toggle_pause(), the real production path), the same keys DO
## work -- proves the fix did not also silence the list while it is
## genuinely on screen.
func test_shown_menu_list_responds_to_arrow_and_enter_keys() -> void:
	PauseUi.toggle_pause()
	var list: MeMenuList = PauseUi._menu_list
	assert_true(list.is_visible_in_tree(), "test setup: toggle_pause should show the menu list")

	# Array-boxed for the same by-value-capture reason as the hidden-list
	# test above.
	var chosen_index := [-1]
	var on_chosen := func(i): chosen_index[0] = i
	list.chosen.connect(on_chosen)

	var down := InputEventKey.new()
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	down.echo = false
	list._unhandled_input(down)
	assert_eq(list._selected_index, 1, "Down did not move the selection while shown")

	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	enter.echo = false
	list._unhandled_input(enter)

	list.chosen.disconnect(on_chosen)
	assert_eq(chosen_index[0], 1, "Enter did not fire chosen with the selected index while shown")

## FIX 6a (final whole-branch review): Esc while the settings page is open
## under pause is the CANCEL path, not a second toggle_pause() -- confirmed
## at the _unhandled_input() level (pause_ui.gd's `if _showing_settings:`
## branch) exactly like the two Esc tests above.
func test_esc_while_settings_open_under_pause_cancels_back_to_the_list() -> void:
	PauseUi.toggle_pause()
	PauseUi._show_settings()
	assert_true(PauseUi._showing_settings, "test setup: settings page should be open")

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	esc.echo = false
	PauseUi._unhandled_input(esc)

	assert_false(PauseUi._showing_settings, "Esc over the settings page did not cancel back to the list")
	assert_true(get_tree().paused, "Esc-cancel out of settings must not also resume the game")
	assert_true(PauseUi._menu_list.is_visible_in_tree(), "the menu list should be back on screen after Esc-cancel")

## FIX 6b (final whole-branch review): _go_to_main_menu() unpauses BEFORE
## requesting the scene change, not after -- change_scene_to_file() is
## deferred, so the opposite order would leave the tree paused for the rest
## of the frame while the old scene is still current. Exercised through the
## real handler with PauseUi's own _change_scene seam stubbed (same shape as
## MainMenu._change_scene), so this never actually swaps GUT's runner scene.
func test_go_to_main_menu_unpauses_before_requesting_the_scene_change() -> void:
	PauseUi.toggle_pause()
	assert_true(get_tree().paused, "test setup: tree should be paused")

	var requested := [""]
	PauseUi._change_scene = func(path): requested[0] = path

	PauseUi._go_to_main_menu()

	assert_false(get_tree().paused, "_go_to_main_menu did not unpause the tree before requesting the scene change")
	assert_eq(requested[0], PauseUi.MAIN_MENU_SCENE, \
		"_go_to_main_menu did not request scenes/ui/main_menu.tscn through the change-scene seam")

## FIX 6c (final whole-branch review): _resume() honors a current scene's
## capture_mouse = false (Arena's own contract, arena.gd) rather than always
## grabbing the cursor. Stood in with a bare Node + a runtime-attached script
## rather than a real Arena, which needs a whole level built around it.
func test_resume_honors_capture_mouse_false_on_the_current_scene() -> void:
	PauseUi.toggle_pause()
	assert_true(get_tree().paused, "test setup: tree should be paused")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "test setup: pausing should have released the mouse")

	var stand_in_script := GDScript.new()
	stand_in_script.source_code = "extends Node\nvar capture_mouse: bool = false\n"
	stand_in_script.reload()
	var stand_in := Node.new()
	stand_in.set_script(stand_in_script)
	# Direct child of root, not add_child_autofree() under the test node --
	# SceneTree.current_scene requires that (verified empirically, same as
	# test_esc_is_a_no_op_while_the_main_menu_is_current_scene below).
	get_tree().root.add_child(stand_in)
	var previous_current_scene := get_tree().current_scene
	get_tree().current_scene = stand_in

	PauseUi._resume()

	get_tree().current_scene = previous_current_scene
	stand_in.queue_free()

	assert_false(get_tree().paused, "_resume did not unpause the tree")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, \
		"resume must honor capture_mouse=false and leave the mouse visible rather than capturing it")

## The per-player half of SettingsStore (see settings_store.gd's split-in-two
## comment): Player.setup() applies the saved camera sensitivity/FOV onto its
## own MovementConfig once one exists. Not a pause test, but lives here as
## the third of this task's three required intents.
func test_player_setup_applies_saved_camera_sensitivity() -> void:
	var saved := SettingsStore.defaults()
	saved.sensitivity = 0.0044
	SettingsStore.save_settings(saved)

	var world := TestWorld.build(get_tree(), MovementConfig.new())

	assert_eq(world["player"].config.camera.mouse_sensitivity, 0.0044, \
		"Player.setup() did not apply the saved sensitivity via SettingsStore")

	TestWorld.teardown(world)


# ---------------------------------------------------------------------------
# MeSettingsMenu (Task 4 of the menu feature): edits happen on a working copy
# until 保存设置 writes it to SettingsStore -- 取消 discards it, 默认 resets
# the in-memory copy (and every control) without ever touching disk. Driven
# directly through the handler methods rather than synthesized HSlider drags/
# button clicks, matching this task's brief ("控件操作直接调其 set_value/模拟
# signal"). Hermetic like the SettingsStore tests above: before_each/
# after_each already clear user://settings.cfg around every test in this file.
# ---------------------------------------------------------------------------

func test_settings_menu_save_persists_the_changed_value() -> void:
	var menu := MeSettingsMenu.new()
	add_child_autofree(menu)
	await step(1)

	menu._on_slider_changed(0.0077, "sensitivity")
	menu._on_save_pressed()

	var loaded := SettingsStore.load_settings()
	assert_eq(loaded.sensitivity, 0.0077, "保存设置 did not persist the changed sensitivity")

func test_settings_menu_cancel_discards_the_change() -> void:
	var menu := MeSettingsMenu.new()
	add_child_autofree(menu)
	await step(1)

	menu._on_slider_changed(0.0077, "sensitivity")
	menu._on_cancel_pressed()

	assert_false(FileAccess.file_exists(SettingsStore.path), "取消 must not write settings.cfg")
	assert_eq(SettingsStore.load_settings().sensitivity, SettingsStore.defaults().sensitivity, \
		"取消 must not leave the cancelled change behind")

func test_settings_menu_default_resets_controls_without_saving() -> void:
	var menu := MeSettingsMenu.new()
	add_child_autofree(menu)
	await step(1)

	menu._on_slider_changed(0.0077, "sensitivity")
	menu._on_default_pressed()

	var slider: HSlider = menu._sliders["sensitivity"]
	assert_almost_eq(slider.value, SettingsStore.defaults().sensitivity, 0.00001, \
		"默认 did not reset the sensitivity slider's displayed value")
	assert_false(FileAccess.file_exists(SettingsStore.path), "默认 must not write settings.cfg")


# ---------------------------------------------------------------------------
# MainMenu (Task 5 of the menu feature): the project's front-door scene. Its
# _ready() builds the whole tree, kicks off the entrance choreography, and --
# on this machine -- also loads a real silhouette body, since
# scenes/player/profiles/local.cfg here points at vrm_test.tres. These tests
# are written to pass either way (model present or the fresh-checkout
# degrade path with none), per the brief's headless caveat: nothing here
# asserts on the silhouette itself, only on the UI structure and the two
# behavior seams.
#
# HONEST TEST CHOICE (开始 handler): a real change_scene_to_file() mid-suite
# would swap out GUT's own runner scene, which is exactly the kind of
# disruption the brief warns about. MainMenu exposes _change_scene as a
# swappable Callable seam for this reason (defaults to the real thing) --
# _on_start_pressed() below is called directly and the test asserts the seam
# was invoked with scenes/main.tscn, never touching the actual scene tree.
# ---------------------------------------------------------------------------

func test_main_menu_builds_without_error_and_skip_entrance_settles_the_list() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(3)

	menu._skip_entrance()

	assert_true(menu._menu_list.is_visible_in_tree(), \
		"the menu list is not visible in tree once the entrance is skipped")
	assert_eq(menu._menu_list._labels.size(), 3, \
		"the main menu list should have exactly 开始/设置/退出")

func test_start_pressed_requests_the_scene_change_via_the_seam() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(1)

	var requested := [""]
	menu._change_scene = func(path): requested[0] = path

	menu._on_start_pressed()

	assert_eq(requested[0], MainMenu.MAIN_SCENE, \
		"开始 did not request scenes/main.tscn through the change-scene seam")

## PauseUi's main-menu guard (_is_main_menu_scene()) now prefers `is
## MainMenu` over the node-name fallback it used before this task's
## class_name existed -- see pause_ui.gd. Exercised through the real
## get_tree().current_scene + the real _unhandled_input() path rather than
## calling the guard function directly, since current_scene is a plain
## settable property here (confirmed empirically: GUT itself never sets one,
## per pause_ui.gd's own comment) and swapping it briefly is the honest way
## to exercise the exact branch production code takes.
##
## NOT add_child_autofree(): SceneTree.set_current_scene() asserts its
## argument is a direct child of the tree's root (verified empirically --
## the engine errors "p_scene->get_parent() != root" otherwise), and GUT
## parents add_child_autofree() nodes under the test itself, not under root.
## Parented directly here instead, and freed by hand at the end.
func test_esc_is_a_no_op_while_the_main_menu_is_current_scene() -> void:
	assert_false(get_tree().paused, "test setup: tree was already paused")
	var menu := MainMenu.new()
	get_tree().root.add_child(menu)
	await step(1)

	var previous_current_scene := get_tree().current_scene
	get_tree().current_scene = menu

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	esc.echo = false
	PauseUi._unhandled_input(esc)

	get_tree().current_scene = previous_current_scene
	menu.queue_free()

	assert_false(get_tree().paused, \
		"Esc must be a no-op while a MainMenu is the current scene")
