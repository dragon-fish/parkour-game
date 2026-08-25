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

func before_each() -> void:
	_delete_settings_file()

func after_each() -> void:
	_delete_settings_file()
	# Unconditional pause/mouse-mode cleanup, run for EVERY test in this file
	# (not just the PauseUi ones below) so a failed assertion mid-test never
	# leaves the tree paused for every suite that runs after this one -- a
	# stuck get_tree().paused = true stalls ParkourTest.step()'s physics_frame
	# await across the whole rest of the process.
	get_tree().paused = false
	PauseUi.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _delete_settings_file() -> void:
	if FileAccess.file_exists(SettingsStore.PATH):
		DirAccess.remove_absolute(SettingsStore.PATH)

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
