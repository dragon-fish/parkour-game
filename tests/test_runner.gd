extends SceneTree

# Headless test entry point. Discovers every tests/test_*.gd, runs each
# `test_` method on a fresh instance, and exits non-zero if anything failed.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tests/test_runner.gd

const TEST_DIR := "res://tests"

func _initialize() -> void:
	_run_all()

func _run_all() -> void:
	var total_checks := 0
	var all_failures: Array[String] = []
	var files := _discover()

	for path in files:
		var script: GDScript = load(path)
		var case = script.new()
		case.tree = self
		var ran := 0
		for m in case.get_method_list():
			var method_name: String = m.name
			if not method_name.begins_with("test_"):
				continue
			ran += 1
			await case.call(method_name)
			for f in case.failures:
				all_failures.append("%s::%s  %s" % [path.get_file(), method_name, f])
			case.failures.clear()
		total_checks += case.checks
		print("  %-32s %d test(s)" % [path.get_file(), ran])

	print("")
	print("checks: %d   failures: %d" % [total_checks, all_failures.size()])
	for f in all_failures:
		print("  FAIL  ", f)
	quit(1 if all_failures.size() > 0 else 0)

func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("cannot open %s" % TEST_DIR)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			if name != "test_runner.gd" and name != "test_case.gd":
				out.append("%s/%s" % [TEST_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
