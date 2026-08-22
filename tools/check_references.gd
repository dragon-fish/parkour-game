extends SceneTree

# Loads every scene and resource in the project and reports the ones that come
# back broken or hollow.
#
# WHY THIS EXISTS: a reference can vanish without anything failing. Godot
# rewrites hand-written .tres files whenever it loads and saves them -- filling
# in uids, dropping fields that equal their defaults, typing arrays -- and if an
# ext_resource does not resolve during that pass it is simply gone from the
# file afterwards. No error, no warning, and the resource still loads fine; it
# just has a null where a model used to be. One of this project's BodyProfiles
# lost its entire `scene` that way and it was noticed by accident, days later,
# while renaming something else.
#
# The command line has no rename that fixes references either -- that is an
# editor-only facility -- so anything moved or renamed from outside has to be
# checked afterwards. This is that check.
#
#   godot --headless --script res://tools/check_references.gd
#
# Exit code 1 if anything is broken, so it can gate a commit.

const SKIP_DIRS: Array[String] = ["res://.godot", "res://addons"]

var _checked := 0
var _problems: Array[String] = []

func _init() -> void:
	_walk("res://")
	print("checked %d scenes and resources" % _checked)
	if _problems.is_empty():
		print("all references resolve")
		quit(0)
		return
	print("%d PROBLEM(S):" % _problems.size())
	for problem in _problems:
		print("  " + problem)
	quit(1)

func _walk(path: String) -> void:
	for skip in SKIP_DIRS:
		if path.begins_with(skip):
			return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full: String = path.path_join(name) if path != "res://" else "res://" + name
		if dir.current_is_dir():
			if not name.begins_with("."):
				_walk(full)
		elif name.get_extension() in ["tscn", "tres", "scn", "res"]:
			_check(full)
		name = dir.get_next()
	dir.list_dir_end()

func _check(path: String) -> void:
	_checked += 1
	# Missing dependencies are the loud failure: the file names something that
	# is not there any more.
	var missing := ResourceLoader.get_dependencies(path)
	for dependency in missing:
		# "uid::type::path" or "type::path", depending on how it was written.
		var parts := String(dependency).split("::")
		var target: String = parts[parts.size() - 1]
		if target.is_empty() or ResourceLoader.exists(target):
			continue
		_problems.append("%s -> missing %s" % [path, target])

	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		_problems.append("%s -> failed to load" % path)
		return

	# And the QUIET one, which is the reason this file exists: a BodyProfile
	# that loads perfectly well with nothing in the slot that names its model.
	if resource is BodyProfile and (resource as BodyProfile).scene == null:
		_problems.append("%s -> BodyProfile has no scene" % path)
