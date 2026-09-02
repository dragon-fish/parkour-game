extends ParkourTest

# A level that hands control over from behind the body. Two things are
# asserted and both are structural: that saying so puts the rig behind the
# body, and that it does not rewrite what the player chose.

## Per PROCESS: user:// is per project, so two concurrent runs of this suite
## would otherwise write each other's camera preferences.
var _test_prefs: String
var _real_prefs: String
var _arena: Arena

func before_all() -> void:
	_test_prefs = "user://camera_prefs_test_%d.cfg" % OS.get_process_id()
	_real_prefs = CameraRig.prefs_path
	CameraRig.prefs_path = _test_prefs

func after_all() -> void:
	_delete_prefs()
	CameraRig.prefs_path = _real_prefs

func after_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_delete_prefs()

func _delete_prefs() -> void:
	if FileAccess.file_exists(CameraRig.prefs_path):
		DirAccess.remove_absolute(CameraRig.prefs_path)

func _arena_starting_in(third: bool) -> Arena:
	var arena: Arena = preload("res://scenes/main.tscn").instantiate()
	arena.start_in_third_person = third
	add_child_autofree(arena)
	await step(2)
	_arena = arena
	return arena

func test_a_level_can_start_the_camera_behind_the_body() -> void:
	var arena: Arena = await _arena_starting_in(true)
	assert_true(arena.player.camera_rig.third_person,
		"start_in_third_person did not put the rig in third person")

func test_starting_behind_the_body_does_not_rewrite_the_saved_preference() -> void:
	# The player's own choice outlives a visit to a level that starts him
	# somewhere else. Saving here would silently flip it for every other level.
	var before := ConfigFile.new()
	before.set_value("third_person", "on", false)
	before.save(CameraRig.prefs_path)
	var arena: Arena = await _arena_starting_in(true)
	# The level's pin still has to win THIS SESSION -- if it were applied
	# before load_preferences(), the loaded false would clobber it back.
	assert_true(arena.player.camera_rig.third_person,
		"the loaded preference overrode the level's own view -- applied in the wrong order")
	var after := ConfigFile.new()
	assert_eq(after.load(CameraRig.prefs_path), OK, "the preferences file disappeared")
	assert_false(bool(after.get_value("third_person", "on", true)),
		"the level saved its own view over the player's saved preference")

func test_a_level_that_says_nothing_leaves_the_preference_alone() -> void:
	# Every existing level must be untouched by this feature.
	#
	# BOTH DIRECTIONS, and that is what makes this catch anything. Asserting
	# only the saved-true case cannot tell "the preference decided" apart from
	# "the flag was ignored and every level starts behind the body", because
	# the two agree on the answer.
	for saved_third in [true, false]:
		var saved := ConfigFile.new()
		saved.set_value("third_person", "on", saved_third)
		saved.save(CameraRig.prefs_path)
		var arena: Arena = await _arena_starting_in(false)
		assert_eq(arena.player.camera_rig.third_person, saved_third,
			"a level with the flag off did not leave the saved preference (%s) alone" % saved_third)
		arena.queue_free()
		await step(1)
