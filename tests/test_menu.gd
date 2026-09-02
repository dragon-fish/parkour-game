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
## ONE FILE PER PROCESS, not one file. user:// is per PROJECT, not per run,
## so a fixed name here is shared by every Godot instance on the machine -- and
## two runs of this suite at once then trample each other's settings mid-test.
##
## MEASURED, and it is what a long-standing intermittent failure turned out to
## be. Two full runs started together fail exactly two cases,
## test_player_setup_applies_saved_camera_sensitivity (0.0022 where 0.0044 was
## saved) and test_keeping_a_display_change_leaves_it_in_place (the size
## reverted), while a run on its own is green. The symptom looked like timing --
## a slow run was a failing run -- but slowness was the other process competing
## for CPU, not the cause: it was the co-runner's writes.
##
## Built at run time rather than as a const, because that is the only way to
## reach the process id.
var _test_settings_path: String
var _real_settings_path: String
## Same redirect-away-from-the-real-file reasoning as SettingsStore.path
## above, for ProgressStore: PauseUi._refresh_entries() reads
## ProgressStore.tutorial_finished() on every pause, so any test that pauses
## would otherwise read (and could leave finished) the author's real
## user://progress.cfg.
var _test_progress_path: String
var _real_progress_path: String

func before_all() -> void:
	_test_settings_path = "user://settings_test_%d.cfg" % OS.get_process_id()
	_real_settings_path = SettingsStore.path
	SettingsStore.path = _test_settings_path
	_test_progress_path = "user://progress_test_%d.cfg" % OS.get_process_id()
	_real_progress_path = ProgressStore.path
	ProgressStore.path = _test_progress_path

func after_all() -> void:
	_delete_settings_file()
	SettingsStore.path = _real_settings_path
	_delete_progress_file()
	ProgressStore.path = _real_progress_path

func before_each() -> void:
	_delete_settings_file()
	_delete_progress_file()

func after_each() -> void:
	_delete_settings_file()
	_delete_progress_file()
	# Session-only and static, so unlike the file above it survives a deleted
	# progress.cfg: left true by a test that failed mid-way it would send every
	# later front-door test down the tutorial branch.
	ProgressStore.replay_requested = false
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
	# Same reasoning as the two lines above, for the pending-scene-change guard
	# (test_go_to_main_menu_unpauses_before_requesting_the_scene_change below):
	# a stuck true would silently no-op every toggle_pause() in every test
	# that runs after it.
	PauseUi._pending_scene_change = false
	PauseUi._change_scene = Callable(PauseUi, "_real_change_scene")

func _delete_settings_file() -> void:
	if FileAccess.file_exists(SettingsStore.path):
		DirAccess.remove_absolute(SettingsStore.path)

func _delete_progress_file() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)

func test_load_settings_with_no_file_returns_defaults() -> void:
	var loaded := SettingsStore.load_settings()
	assert_eq(loaded, SettingsStore.defaults(), "missing settings.cfg should load as defaults")

func test_save_then_load_round_trips_every_key() -> void:
	var saved := SettingsStore.defaults()
	saved.window_mode = "fullscreen"
	saved.window_size = Vector2i(1920, 1080)
	saved.sensitivity = 0.0035
	saved.fov = 100.0
	saved.volume = 0.5

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
	s.volume = 0.25
	SettingsStore.apply_global(s)

	# 0.25 amplitude is -12.04 dB: the log curve, not a linear slider.
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25), 0.01,
		"apply_global did not put the amplitude through linear_to_db onto the Master bus")

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

## Esc while the settings page is open under pause is the CANCEL path, not a second toggle_pause() -- confirmed
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

## go_to_main_menu() unpauses BEFORE requesting the scene change, not after --
## change_scene_to_file() is deferred, so the opposite order would leave the
## tree paused for the rest of the frame while the old scene is still
## current. Exercised through the real handler with PauseUi's own
## _change_scene seam stubbed (same shape as MainMenu._change_scene), so this
## never actually swaps GUT's runner scene.
func test_go_to_main_menu_unpauses_before_requesting_the_scene_change() -> void:
	PauseUi.toggle_pause()
	assert_true(get_tree().paused, "test setup: tree should be paused")

	# The stub snapshots pause state AT CALL TIME -- asserting after the
	# call cannot pin the order, since both effects are synchronous.
	var requested := [""]
	var paused_at_call := [true]
	PauseUi._change_scene = func(path):
		requested[0] = path
		paused_at_call[0] = get_tree().paused

	PauseUi.go_to_main_menu()

	assert_false(paused_at_call[0],
		"the tree was still paused at the moment the scene change was requested")
	assert_false(get_tree().paused, "go_to_main_menu did not unpause the tree")
	assert_eq(requested[0], PauseUi.MAIN_MENU_SCENE, \
		"go_to_main_menu did not request scenes/ui/main_menu.tscn through the change-scene seam")

## _resume() honors a current scene's
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

func test_replaying_the_tutorial_arms_it_and_returns_to_the_front_door() -> void:
	# Both halves fail silently. Without the flag the click sends the player to
	# a main menu he then clicks past into the menu again -- nothing happens,
	# twice. Without the scene change he stays on the settings page.
	ProgressStore.mark_tutorial_finished()
	ProgressStore.replay_requested = false
	var page := MeSettingsMenu.new()
	add_child_autofree(page)
	await step(1)
	var requested := [""]
	PauseUi._change_scene = func(path): requested[0] = path

	page._on_replay_tutorial_pressed()
	await step(1)

	assert_true(ProgressStore.replay_requested,
		"重玩新手教程 did not arm the next click on the front door")
	assert_eq(requested[0], PauseUi.MAIN_MENU_SCENE,
		"重玩新手教程 did not send the game back to the front door")
	PauseUi._change_scene = Callable(PauseUi, "_real_change_scene")
	PauseUi._pending_scene_change = false
	ProgressStore.replay_requested = false
	_delete_progress_file()

func test_the_settings_page_still_builds_every_row() -> void:
	# The build loop routes a row by key. A key that loses its branch does not
	# come up unbuilt -- _build_slider() unconditionally writes into _sliders
	# no matter what its match statement recognized, so a row that fell through
	# to it still registers as "some known kind". Checking membership in ANY
	# bucket cannot see that; only checking a row landed in EXACTLY the one
	# bucket its own key implies can.
	var page := MeSettingsMenu.new()
	add_child_autofree(page)
	await step(1)
	for row in MeSettingsMenu._ROWS:
		var key: String = row["key"]
		var in_slider: bool = page._sliders.has(key)
		var in_stepper: bool = page._stepper_value_labels.has(key)
		if key in MeSettingsMenu._ACTION_KEYS:
			assert_false(in_slider, "action row %s was ALSO built as a slider" % key)
			assert_false(in_stepper, "action row %s was ALSO built as a stepper" % key)
		elif key in ["window_mode", "window_size", "antialiasing"]:
			assert_true(in_stepper, "stepper row %s was not built as a stepper" % key)
			assert_false(in_slider, "stepper row %s was ALSO built as a slider" % key)
		else:
			assert_true(in_slider, "slider row %s was not built as a slider" % key)
			assert_false(in_stepper, "slider row %s was ALSO built as a stepper" % key)


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
	assert_eq(menu._menu_list._labels.size(), 4, \
		"the main menu list should have exactly 开始/角色/设置/退出")

func test_start_pressed_requests_the_scene_change_via_the_seam() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(1)

	var requested := [""]
	menu._change_scene = func(path): requested[0] = path

	menu._on_start_pressed()

	# Asserted against the menu's OWN target, not a hardcoded path: what this
	# test is about is that the press goes through the change-scene seam at
	# all. Which level the seam is currently pointed at is a level-authoring
	# decision and changes while a new one is being built.
	assert_eq(requested[0], menu._target_scene, \
		"开始 did not request its target scene through the change-scene seam")

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

func test_a_rescue_resume_on_the_main_menu_never_captures_the_cursor() -> void:
	# FIX 5's second half (pause_ui.gd _current_scene_wants_mouse_capture's
	# MainMenu branch): if a pause ever survives onto the main menu, 继续
	# must leave the cursor free -- a menu needs a pointer, not a捕获.
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	get_tree().root.add_child(menu)
	var previous := get_tree().current_scene
	get_tree().current_scene = menu
	# toggle_pause may legitimately no-op on the main menu (the Esc guard),
	# so the paused state is forced directly -- the scenario is "a pause
	# SURVIVED onto the menu", however it got there.
	get_tree().paused = true
	PauseUi._resume()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE,
		"resuming on the main menu captured the mouse")
	assert_false(get_tree().paused, "the rescue resume did not unpause")
	get_tree().current_scene = previous
	menu.queue_free()
	await step(1)

# --- a display change is on probation until somebody says it is fine ---------
#
# THESE NEVER WAIT THE REAL FIFTEEN SECONDS. A suite that actually slept
# through every timeout would be unusable. The countdown lives in
# _process(delta), so a test
# hands it one big delta and the timeout has happened -- the same trick the
# input tests use when they call _unhandled_input() directly.

func _settings_on_probation() -> Array:
	# A page whose working copy differs from disk in a DISPLAY key, with the
	# probation already begun -- _on_save_pressed() skips it in headless (no
	# window to lose), so the dialog is opened here directly.
	var previous := SettingsStore.defaults()
	previous.window_size = Vector2i(1280, 720)
	SettingsStore.save_settings(previous)
	var menu := MeSettingsMenu.new()
	add_child_autofree(menu)
	await step(2)
	menu._working.window_size = Vector2i(2560, 1440)
	SettingsStore.save_settings(menu._working)
	menu._ask_to_keep_display(previous)
	return [menu, previous]

func test_an_unconfirmed_display_change_reverts_itself() -> void:
	var bits: Array = await _settings_on_probation()
	var menu: MeSettingsMenu = bits[0]
	var previous: Dictionary = bits[1]

	menu._process(MeSettingsMenu.DISPLAY_REVERT_SECONDS + 1.0)

	assert_eq(menu._working.window_size, previous.window_size,
		"the working copy kept the size nobody confirmed")
	assert_eq(SettingsStore.load_settings().window_size, previous.window_size,
		"the unconfirmed size was left on disk, so the next launch would use it")

func test_keeping_a_display_change_leaves_it_in_place() -> void:
	var bits: Array = await _settings_on_probation()
	var menu: MeSettingsMenu = bits[0]

	menu._keep_display()
	menu._process(MeSettingsMenu.DISPLAY_REVERT_SECONDS + 1.0)

	assert_eq(SettingsStore.load_settings().window_size, Vector2i(2560, 1440),
		"a confirmed size was reverted anyway")


# ---------------------------------------------------------------------------
# The pre-entrance input window. MainMenu._ready() awaits six process frames
# (the framing solve needs a live skeleton pose) before _play_entrance()
# schedules anything, while _entrance_active starts true and
# _unhandled_input is live the moment the node enters the tree. A key press
# landing in that window -- exactly the window a white transition covers --
# must not leave the menu in a state _ready() then walks back over.
# ---------------------------------------------------------------------------

func test_a_key_before_the_entrance_is_scheduled_does_not_replay_the_prompt() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(2)

	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	key.echo = false
	menu._unhandled_input(key)

	# Past _ready()'s six frames and past LOGO_HOLD * 0.5, which is where
	# _show_click_prompt() fires if the entrance was scheduled after the skip.
	await step(60)

	# Asserted as coherence rather than as one outcome: whether that key is
	# swallowed or honoured is a decision, but the two states must never
	# overlap, and the menu must never end up unable to take input at all.
	var settled: bool = menu._menu_list.is_visible_in_tree()
	assert_false(settled and menu._click_prompt.visible,
		"the click prompt is breathing over a menu that has already settled")
	assert_true(settled or menu._entrance_active,
		"the menu neither settled nor still takes input -- nothing can reach it")

func test_the_pause_menu_sits_above_the_screen_effects() -> void:
	# A menu you cannot read is a menu that is not there. ScreenEffects sits
	# high on purpose -- a death blackout has to cover the crosshair and the
	# HUD -- so the pause layer has to clear it, and the two numbers live in
	# different files with nothing but this test tying them together.
	var fx := ScreenEffects.new()
	add_child_autofree(fx)
	await step(1)
	assert_gt(PauseUi.layer, fx.layer, \
		"the pause menu is underneath the screen effects, so a blur or a fade hides it")


# ---------------------------------------------------------------------------
# The pause menu's rows. MeMenuList only ever reports an INDEX into the labels
# it was handed, so the table that produced those labels is the only thing
# that can say what an index means.
# ---------------------------------------------------------------------------

func test_every_pause_row_names_a_method_that_exists() -> void:
	# A typo'd handler is SILENT: call() on a missing method logs an engine
	# error, and this suite's failure_error_types does not include those, so
	# the row would simply do nothing forever.
	for entry in PauseUi._ENTRIES:
		assert_true(PauseUi.has_method(entry.handler),
			"pause row %s points at a method that does not exist: %s" % [entry.label, entry.handler])

func test_choosing_a_row_runs_that_rows_handler() -> void:
	# Dispatch wired to the wrong index puts 退出游戏 on 设置. Found by name,
	# never by a hardcoded number -- that is the whole point of the table.
	PauseUi.toggle_pause()
	var settings_at := -1
	for i in PauseUi._entries.size():
		if PauseUi._entries[i].handler == &"_show_settings":
			settings_at = i
	assert_gt(settings_at, -1, "test setup: no 设置 row on the pause menu")
	PauseUi._on_chosen(settings_at)
	assert_true(PauseUi._showing_settings,
		"choosing 设置 did not open the settings page")
	PauseUi._on_settings_closed()
	PauseUi._resume()


# ---------------------------------------------------------------------------
# 回主菜单 is withheld until the tutorial has been finished once -- see
# ProgressStore.tutorial_finished(). ProgressStore.path is redirected to a
# per-process file in before_all()/after_all() above, same as
# SettingsStore.path, and cleared in before_each()/after_each(), so these
# never touch the author's real progress.cfg and never leak a finished
# tutorial into a later test when an assertion above fails.
# ---------------------------------------------------------------------------

func test_the_main_menu_row_is_absent_until_the_tutorial_is_finished() -> void:
	# Until it has been finished once the tutorial IS the front door, so there
	# is nothing behind it to go back to.
	PauseUi.toggle_pause()
	for entry in PauseUi._entries:
		assert_ne(entry.handler, &"go_to_main_menu",
			"回主菜单 is on the pause menu before the tutorial has ever been finished")
	PauseUi._resume()

func test_hiding_the_main_menu_row_does_not_renumber_the_rows_below_it() -> void:
	# THE BUG THE WHOLE TABLE EXISTS FOR. With positional dispatch, omitting
	# 回主菜单 moved 退出游戏 up onto its number, so the last row quit to the
	# main menu -- or, the other way round, quit the game outright.
	PauseUi.toggle_pause()
	var last: int = PauseUi._entries.size() - 1
	assert_eq(PauseUi._entries[last].handler, &"_show_quit_confirm",
		"the last pause row is no longer 退出游戏 once a row above it is hidden")
	PauseUi._resume()

func test_choosing_the_last_row_still_runs_quit_once_a_row_above_it_is_hidden() -> void:
	# The dispatch-level twin of the renumbering test above. That one checks
	# the TABLE still names the right handler; this one actually drives the
	# choice through _on_chosen() and checks what ran -- the table alone would
	# not have caught a regression back to matching by position, since a
	# hardcoded index 4 (回主菜单's old slot) still exists and would silently
	# fire go_to_main_menu() instead.
	PauseUi.toggle_pause()
	var last: int = PauseUi._entries.size() - 1
	PauseUi._on_chosen(last)
	assert_true(PauseUi._quit_confirm != null and PauseUi._quit_confirm.visible,
		"choosing the last row once 回主菜单 is hidden did not run 退出游戏's handler")
	if PauseUi._quit_confirm != null:
		PauseUi._quit_confirm.visible = false
	PauseUi._resume()

func test_the_main_menu_row_comes_back_once_the_tutorial_is_finished() -> void:
	# Rebuilt on every pause rather than only at boot: the tutorial is finished
	# DURING a session, and the row has to appear without a restart.
	ProgressStore.mark_tutorial_finished()
	PauseUi.toggle_pause()
	var found := false
	for entry in PauseUi._entries:
		if entry.handler == &"go_to_main_menu":
			found = true
	assert_true(found, "回主菜单 never came back after the tutorial was finished")
	PauseUi._resume()


# ---------------------------------------------------------------------------
# The first click. It means one of two entirely different things depending on
# whether the tutorial has ever been finished, and the wrong one is a player
# either dumped into a menu he has not earned or trapped in a tutorial he has
# already done.
#
# EIGHT FRAMES, not three. MainMenu._ready() awaits six process frames for the
# framing solve before _play_entrance() sets _entrance_active, and
# _unhandled_input() drops every event until it does -- a shorter wait makes
# these tests pass or fail on nothing at all. _prompt_shown is then forced
# rather than waited for: it arrives on LOGO_HOLD * 0.5, half a second later,
# and that half second is the entrance's pacing, not this test's subject.
# ---------------------------------------------------------------------------

func test_the_first_ever_click_goes_straight_into_the_tutorial() -> void:
	_delete_progress_file()
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(8)
	var requested := [""]
	menu._change_scene = func(path): requested[0] = path
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)

	assert_true(menu._entering_tutorial,
		"the first click did not take the tutorial branch")
	assert_eq(requested[0], MainMenu.LEVEL_0_SCENE,
		"the tutorial branch did not ask for the tutorial level")
	assert_false(menu._menu_list.visible,
		"the menu list appeared on a launch that should have had no menu at all")

func test_the_first_click_opens_the_menu_once_the_tutorial_is_finished() -> void:
	ProgressStore.mark_tutorial_finished()
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(8)
	var requested := [""]
	menu._change_scene = func(path): requested[0] = path
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)

	assert_false(menu._entering_tutorial,
		"a finished player was sent back into the tutorial")
	assert_true(menu._beat_rise_fired,
		"the ordinary entrance did not play")
	# The menu branch loads NOTHING on the click: 开始 is still ahead of it.
	# Without this the branch could take the tutorial's load path and still
	# look right, since _entering_tutorial would only be a flag nobody read.
	assert_eq(requested[0], "",
		"the ordinary entrance requested a scene change before 开始 was ever pressed")

func test_a_replay_request_takes_the_tutorial_branch_even_when_finished() -> void:
	ProgressStore.mark_tutorial_finished()
	ProgressStore.replay_requested = true
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(8)
	menu._change_scene = func(_path): pass
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)

	assert_true(menu._entering_tutorial,
		"重玩新手教程 did not survive the trip back to the front door")

func test_a_second_click_during_the_tutorial_opening_never_summons_the_menu() -> void:
	# A REPEATED SHOW MUST BE SKIPPABLE, and the only skip available on this
	# path is dropping the hold. Falling through to _skip_entrance() instead
	# settles the MENU -- column, dressing and all -- on top of an opening
	# that is already on its way into the level.
	ProgressStore.replay_requested = true
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(8)
	menu._change_scene = func(_path): pass
	menu._prompt_shown = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._unhandled_input(click)
	await step(2)
	assert_gt(menu._tutorial_hold, 0.0, "test setup: the opening was not holding")

	menu._unhandled_input(click)
	await step(2)

	assert_eq(menu._tutorial_hold, 0.0,
		"an impatient click during the tutorial opening did not drop the hold")
	assert_false(menu._menu_list.visible,
		"an impatient click during the tutorial opening settled the menu over it")

## THE ONE FAILURE NOTHING ELSE CAN SEE. Every other test here asserts against
## _target_scene or the constants themselves, so a mistyped path stays green
## through the whole suite and breaks the game at the instant the player
## clicks. Iterated rather than compared to written-out values: an equality
## test on the paths would redden the moment a level is legitimately moved,
## which is the opposite of what this is for.
##
## SCENES ONLY. BODY_PROFILE and LOCAL_PROFILE_CONFIG are machine-local
## (untracked, absent on a fresh checkout by design -- see
## _resolve_body_profile), so requiring them to exist would fail the suite on
## exactly the machines this project promises to run on.
func test_every_scene_path_the_main_menu_names_actually_exists() -> void:
	# Through a Script-typed local, not MainMenu.get_script_constant_map():
	# get_script_constant_map() is an instance method on Script, and calling it
	# on the class global directly is a parse error.
	var script: GDScript = MainMenu
	var constants: Dictionary = script.get_script_constant_map()
	var checked := 0
	for key in constants:
		var value = constants[key]
		if not (value is String and (value as String).ends_with(".tscn")):
			continue
		checked += 1
		assert_true(ResourceLoader.exists(value),
			"MainMenu.%s points at %s, which is not a scene that exists" % [key, value])
	assert_gt(checked, 0,
		"no scene-path constant was found on MainMenu -- this test checked nothing")
