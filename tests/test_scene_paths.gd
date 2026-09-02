extends ParkourTest

# Every scene path a script names as a constant must lead somewhere.
#
# A MISTYPED PATH IS INVISIBLE UNTIL A PLAYER WALKS INTO IT. Nothing in a
# scene path is checked at parse time, so a constant pointing at a file that
# is not there compiles, tests green, and fails at the one moment it is used
# -- the click on 开始, the way out of the thanks page, 回主菜单. Each of those
# is a dead end for the player and a silent one for everybody else.
#
# WALKS THE FOLDERS RATHER THAN A LIST, so a script written next week is
# covered without anyone remembering to add it here. What is asserted is that
# the path resolves, never what the path IS -- pinning the value would redden
# this the moment a scene is moved, which is the author's business and not a
# defect.

const SEARCHED := ["res://scripts/ui", "res://scripts/level"]

func test_every_scene_path_named_in_a_constant_resolves() -> void:
	var checked := 0
	for folder in SEARCHED:
		var scripts := _scripts_under(folder)
		# PER FOLDER, NOT ACROSS ALL OF THEM. A total taken over both would
		# stay non-zero after one folder was renamed away, and the scripts that
		# used to live in it would quietly stop being checked at all.
		assert_gt(scripts.size(), 0, "%s holds no scripts, so nothing there was checked" % folder)
		for path in scripts:
			var script: GDScript = load(path)
			assert_not_null(script, "could not load %s" % path)
			if script == null:
				continue
			for name in script.get_script_constant_map():
				var value: Variant = script.get_script_constant_map()[name]
				if not (value is String) or not (value as String).ends_with(".tscn"):
					continue
				checked += 1
				assert_true(ResourceLoader.exists(value),
					"%s.%s points at a scene that does not exist: %s" % [path.get_file(), name, value])
	# WITHOUT THIS THE TEST PASSES BY FINDING NOTHING. A rename of the folders
	# above, or a change in how constants are read, would otherwise turn this
	# into a green check of zero paths.
	assert_gt(checked, 0, "no scene-path constants were found, so nothing was checked")

func _scripts_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append("%s/%s" % [folder, file])
	for sub in dir.get_directories():
		found.append_array(_scripts_under("%s/%s" % [folder, sub]))
	return found
