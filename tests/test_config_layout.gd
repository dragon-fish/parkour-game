extends ParkourTest

# Pins the layout AND the values a fresh MovementConfig hands out, so the
# migration from the old flat resource can be shown to have changed nothing
# but where the numbers live. One representative field per sub-resource --
# this is a structure test, not a re-transcription of the whole table.

func test_a_fresh_config_builds_every_sub_resource() -> void:
	var config := MovementConfig.new()
	assert_true(config.pawn != null, "pawn config missing")
	assert_true(config.camera != null, "camera config missing")
	assert_true(config.walking != null, "walking config missing")
	assert_true(config.jump != null, "jump config missing")
	assert_true(config.falling != null, "falling config missing")
	assert_true(config.landing != null, "landing config missing")
	assert_true(config.slide != null, "slide config missing")
	assert_true(config.crouch != null, "crouch config missing")
	assert_true(config.speed_vault != null, "speed_vault config missing")
	assert_true(config.grab != null, "grab config missing")
	assert_true(config.wall_run != null, "wall_run config missing")
	assert_true(config.wallrun_jump != null, "wallrun_jump config missing")

func test_two_configs_do_not_share_their_sub_resources() -> void:
	# Player.setup() already duplicates the collision capsule for exactly this
	# reason. An @export default built with .new() is evaluated per instance,
	# but that is worth pinning rather than assuming: a shared sub-resource
	# would let one player's F1 slider retune every other player in the scene,
	# and in the test suite, retune the next test file's world.
	var a := MovementConfig.new()
	var b := MovementConfig.new()
	assert_true(a.pawn != b.pawn, "two configs share one PawnConfig instance")
	assert_true(a.slide != b.slide, "two configs share one SlideConfig instance")

func test_migrated_values_are_unchanged() -> void:
	var config := MovementConfig.new()
	# Repinned, not "unchanged": gravity is the one migrated value that turned
	# out to be wrong. 800 is what DefaultGame.ini says; 1600 is what the game
	# does (02 §2.4, measured across 22 jumps).
	assert_almost_eq(config.pawn.gravity, 16.0, 0.0001, "gravity is not the measured 16.0")
	assert_almost_eq(config.pawn.ground_speed, 7.2, 0.0001, "ground_speed moved but changed")
	assert_almost_eq(config.pawn.accel_rate, 61.44, 0.0001, "accel_rate is not the confirmed 61.44")
	assert_almost_eq(config.camera.fov_base, 90.0, 0.0001, "fov_base moved but changed")
	# NOT a migrated value any more: eye_height moved to the confirmed
	# BaseEyeHeight = 76 uu (09 §9.1). Repinned rather than dropped, because
	# tools/player_builder.gd bakes it into player.tscn's CameraRig position --
	# see tests/test_generated_scenes.gd, which is what catches the two going
	# out of step.
	assert_almost_eq(config.camera.eye_height, 0.76, 0.0001, "eye_height is not the confirmed 0.76")
	# The sliding eye must not rise above the crouched capsule's top, so this
	# one is DERIVED from eye_height rather than independent of it. Pinned as a
	# RELATIONSHIP: retuning eye_height alone must not be allowed to silently
	# poke the camera through the low tunnels sliding exists to fit under.
	assert_gt(config.camera.slide_camera_drop, config.camera.eye_height, \
		"slide_camera_drop no longer covers eye_height -- the sliding eye now sits above the crouched capsule")

func test_move_config_defaults_are_neutral() -> void:
	# A Move that declares nothing must behave exactly as it did before this
	# layer existed: full speed, full friction, no cooldown, no look clamp.
	var cfg := MoveConfig.new()
	assert_almost_eq(cfg.speed_modifier, 1.0, 0.0001, "default speed_modifier is not neutral")
	assert_almost_eq(cfg.friction_modifier, 1.0, 0.0001, "default friction_modifier is not neutral")
	assert_almost_eq(cfg.redo_move_time, 0.0, 0.0001, "default redo_move_time is not zero")
	assert_true(not cfg.constrain_look, "look is constrained by default")

func test_balance_and_ledge_walk_are_on_the_aggregate() -> void:
	var config := MovementConfig.new()
	assert_not_null(config.balance, "MovementConfig must carry a BalanceConfig")
	assert_not_null(config.ledge_walk, "MovementConfig must carry a LedgeWalkConfig")
	assert_true(config.balance is BalanceConfig)
	assert_true(config.ledge_walk is LedgeWalkConfig)

func test_the_two_line_walks_declare_the_original_speed_modifiers() -> void:
	var config := MovementConfig.new()
	# [ME:CONFIRMED] TdMove_Balance 0.34, TdMove_LedgeWalk 0.10.
	assert_almost_eq(config.balance.speed_modifier, 0.34, 0.001)
	assert_almost_eq(config.ledge_walk.speed_modifier, 0.10, 0.001)

func test_spring_board_is_on_the_aggregate() -> void:
	var config := MovementConfig.new()
	assert_not_null(config.spring_board, "MovementConfig must carry a SpringBoardConfig")
	assert_true(config.spring_board is SpringBoardConfig)
	# The throw's own numbers, straight off the CDO. Declared, not defaulted.
	assert_almost_eq(config.spring_board.jump_z, 9.5, 0.001)
	assert_true(config.spring_board.check_for_grab, "the rise must keep the original's grab check")

func test_the_default_preset_keeps_the_ported_ini_values_of_crouch_and_slide() -> void:
	# The preset is what Arena loads, so a value it declares overrides the
	# ported one silently. These two had drifted from the original's ini
	# ([TdMove_Crouch] SpeedModifier = 0.2; Slide sets no RedoMoveTime, so the
	# [TdMove] 0 holds): the preset must say nothing different from the class.
	var preset := load("res://presets/default.tres") as MovementConfig
	assert_almost_eq(preset.crouch.speed_modifier, CrouchConfig.new().speed_modifier, 0.0001,
		"the default preset overrides Crouch's SpeedModifier")
	assert_almost_eq(preset.slide.redo_move_time, SlideConfig.new().redo_move_time, 0.0001,
		"the default preset gives Slide a RedoMoveTime the original does not have")

## Every config sub-resource a committed MovementConfig preset carries must be
## WRITTEN in the file, not left to the script's `= XxxConfig.new()` default.
##
## The default only exists at runtime. The exporter converts text resources to
## binary inside the editor, where MovementConfig is not a tool script and its
## initialisers never run: a field the .tres leaves out is read as null there
## and written into the shipped .res as an explicit null. Loaded from source the
## same preset is complete, so nothing but an exported build shows it -- and
## there the move's cfg is null: no zipline catch, no pull-up, no jump from a
## hang. DO NOT fix a failure here by filling nulls in at load time; add the
## missing field to the preset as a value-less sub-resource (`script =` only),
## which keeps the move's own defaults in charge.
func test_every_preset_writes_out_every_config_sub_resource() -> void:
	var fields: Array[String] = []
	for prop in MovementConfig.new().get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.type == TYPE_OBJECT:
			fields.append(prop.name)
	assert_gt(fields.size(), 30, "test setup: MovementConfig's fields were not found")
	var presets: Array[String] = _movement_presets("res://presets")
	assert_false(presets.is_empty(), "test setup: no MovementConfig preset under res://presets")
	for path in presets:
		var written: Dictionary = _resource_section_keys(FileAccess.get_file_as_string(path))
		var missing: Array[String] = []
		for field in fields:
			if not written.has(field):
				missing.append(field)
		assert_eq(missing, [] as Array[String],
			"%s leaves these to the script default, so an export ships them null: %s" % [path, missing])

static func _movement_presets(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_movement_presets(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var path: String = dir.path_join(file)
		var text: String = FileAccess.get_file_as_string(path)
		if text.get_slice("\n", 0).contains("script_class=\"MovementConfig\""):
			out.append(path)
	return out

## The property names a text resource's own [resource] section assigns.
static func _resource_section_keys(text: String) -> Dictionary:
	var keys := {}
	var at: int = text.find("\n[resource]\n")
	if at < 0:
		return keys
	for line in text.substr(at + 12).split("\n"):
		if line.begins_with("["):
			break
		var eq: int = line.find(" = ")
		if eq > 0:
			keys[line.substr(0, eq)] = true
	return keys
