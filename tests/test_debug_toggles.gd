extends ParkourTest

# DebugToggles is the F1 panel's on-disk model for which debug overlays were
# left on. Headless and UI-free, same spirit as test_tuning_panel_model.gd --
# no panel, no overlays, just the round trip through ConfigFile.

const TEST_PATH := "user://test_debug_toggles.cfg"
const MISSING_PATH := "user://test_debug_toggles_missing.cfg"

func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

func test_save_then_load_round_trips_every_state() -> void:
	DebugToggles.save_states({"a": true, "b": false}, TEST_PATH)
	var loaded := DebugToggles.load_states(TEST_PATH)
	assert_eq(loaded.get("a"), true, "a should round-trip as true")
	assert_eq(loaded.get("b"), false, "b should round-trip as false")

func test_loading_a_missing_path_returns_an_empty_dictionary() -> void:
	if FileAccess.file_exists(MISSING_PATH):
		DirAccess.remove_absolute(MISSING_PATH)
	var loaded := DebugToggles.load_states(MISSING_PATH)
	assert_true(loaded.is_empty(), "a missing file should load as empty, not an error")
