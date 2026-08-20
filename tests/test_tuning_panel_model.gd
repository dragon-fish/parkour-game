extends ParkourTest

# The panel's own property walk, tested without building any UI. Extracted
# from _build_ui() precisely so it can be: the old version was pure UI code
# and had no test at all.

func _paths(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row in rows:
		out.append(row["path"])
	return out

func test_it_reaches_floats_inside_every_sub_resource() -> void:
	var config := MovementConfig.new()
	var paths := _paths(TuningPanel.collect_tunables(config))
	assert_true(paths.has("pawn.gravity"), "pawn floats not reached")
	assert_true(paths.has("camera.fov_base"), "camera floats not reached")
	assert_true(paths.has("slide.slide_abort_speed"), "per-move floats not reached")
	assert_true(paths.has("wall_run.wall_running_horisontal_acceleration"), "wall_run floats not reached")

func test_inherited_move_config_fields_are_reached_too() -> void:
	# speed_modifier/friction_modifier live on the MoveConfig BASE class, not
	# on CrouchConfig itself. A walk that only reported a resource's own
	# declared properties would silently drop every one of them -- which is
	# most of what makes a move a move.
	var config := MovementConfig.new()
	var paths := _paths(TuningPanel.collect_tunables(config))
	assert_true(paths.has("crouch.speed_modifier"), "inherited MoveConfig fields not reached")
	assert_true(paths.has("slide.friction_modifier"), "inherited friction_modifier not reached")

func test_a_row_can_read_and_write_its_own_value() -> void:
	var config := MovementConfig.new()
	for row in TuningPanel.collect_tunables(config):
		if row["path"] != "pawn.gravity":
			continue
		assert_almost_eq(row["owner"].get(row["property"]), 16.0, 0.0001, "row read the wrong value")
		row["owner"].set(row["property"], 12.0)
		assert_almost_eq(config.pawn.gravity, 12.0, 0.0001, "writing through a row did not reach the config")
		return
	assert_true(false, "no row for pawn.gravity")

func test_non_float_and_non_resource_properties_are_skipped() -> void:
	var config := MovementConfig.new()
	var paths := _paths(TuningPanel.collect_tunables(config))
	# speed_curve is a PackedVector2Array and cannot be driven by a slider;
	# constrain_look is a bool. Neither belongs in the generated UI.
	assert_true(not paths.has("pawn.speed_curve"), "a non-float property leaked into the rows")
	assert_true(not paths.has("slide.constrain_look"), "a bool property leaked into the rows")

func test_every_row_carries_a_default_from_a_fresh_config() -> void:
	# The slider range is default * RANGE_FACTOR, so a row whose default came
	# from the LIVE config would shrink its own range every time a preset with
	# a smaller value was loaded.
	var config := MovementConfig.new()
	config.pawn.gravity = 1.0
	for row in TuningPanel.collect_tunables(config):
		if row["path"] == "pawn.gravity":
			assert_almost_eq(row["default"], 16.0, 0.0001, "default came from the live config, not a fresh one")
			return
	assert_true(false, "no row for pawn.gravity")

func test_preset_round_trip_preserves_a_value_equal_to_a_different_declared_default() -> void:
	# ResourceSaver.save(config, path) -- the old preset format -- omits any
	# property whose CURRENT value equals its DECLARED default. speed_modifier
	# is declared on the MoveConfig base with default 1.0, but CrouchConfig's
	# _init() sets it to 0.4. Tuning crouch's speed_modifier back to exactly
	# 1.0 (the base's default, not crouch's own) would make ResourceSaver
	# treat the property as "unchanged" and omit it from the .tres; reloading
	# would then re-run _init() and silently restore 0.4, losing the tuned
	# value with no error. This is the whole reason the preset format changed
	# to an explicit path->value mapping (TuningPreset) instead of a
	# serialized MovementConfig -- under the old approach this assertion
	# fails.
	#
	# Panel is built directly, never added to the SceneTree: _build_ui() only
	# needs `config` to be set (normally done by Arena's injection, mimicked
	# here by setting it before the call), and building it manually skips the
	# call_deferred("_build_ui") race that _ready() would otherwise set up.
	#
	# Because _ready() is skipped, its DirAccess.make_dir_recursive_absolute()
	# call never runs either -- PRESET_DIR must not be assumed to already
	# exist. On a machine that has never launched the actual game (a fresh
	# checkout, CI), user://presets does not exist yet, and _on_save() below
	# would fail with "Cannot save file ..." instead of exercising the
	# round-trip. Creating it here makes the test hermetic instead of
	# incidentally depending on some earlier run (in-game or another test)
	# having created the directory first.
	DirAccess.make_dir_recursive_absolute(TuningPanel.PRESET_DIR)

	var config := MovementConfig.new()
	var panel := TuningPanel.new()
	panel.config = config
	panel._build_ui()
	var preset_name := "test_round_trip_crouch"
	panel._preset_name.text = preset_name

	config.crouch.speed_modifier = 1.0
	panel._on_save()
	config.crouch.speed_modifier = 0.2
	panel._on_load()

	assert_almost_eq(config.crouch.speed_modifier, 1.0, 0.0001, \
		"crouch speed_modifier did not round-trip through save/load")
	panel.free()

	# Leave no residue next to the owner's real presets.
	var preset_path := "%s/%s.tres" % [TuningPanel.PRESET_DIR, preset_name]
	if FileAccess.file_exists(preset_path):
		DirAccess.remove_absolute(preset_path)
