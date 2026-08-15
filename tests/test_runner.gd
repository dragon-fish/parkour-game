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
		# load() on a script with a parse/syntax error does not reliably return
		# null in Godot 4.7 — it can hand back a GDScript that fails to compile,
		# whose new() is not callable. can_instantiate() catches both cases.
		if script == null or not script.can_instantiate():
			all_failures.append("%s  failed to load (parse/syntax error)" % path.get_file())
			print("  %-32s LOAD FAILED" % path.get_file())
			continue
		var case = script.new()
		# A tests/test_*.gd file that isn't a TestCase (e.g. a fixture helper)
		# would otherwise die on the "case.tree = self" assignment below in a
		# way that silently kills this coroutine instead of raising a normal
		# GDScript error - the SceneTree is left idling forever with nothing
		# left to process, and quit() never runs. Guard it explicitly so a
		# misplaced fixture fails loudly instead of hanging the whole suite.
		if not (case is TestCase):
			all_failures.append("%s  is not a TestCase (does not extend TestCase)" % path.get_file())
			print("  %-32s SKIPPED (not a TestCase)" % path.get_file())
			continue
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

		# Purge anything a broken test left behind. Well-behaved tests already
		# queue_free() their own scene tree and await a frame before
		# returning, but that cleanup only runs when a test reaches its own
		# end. A test that errors out partway (e.g. an unguarded null access,
		# an assertion failure outside check()) skips its own teardown and
		# leaves its player/floor/etc still parented under root. The next
		# test file then builds a fresh world at the origin on top of those
		# leftovers -- e.g. two overlapping capsules physically shoving each
		# other -- corrupting completely unrelated measurements in whatever
		# runs next. This project has no autoloads, so root has no children
		# worth preserving between files; free everything unconditionally and
		# let a frame elapse so the physics server has actually let go of the
		# freed bodies before the next file's tests begin.
		for leftover in root.get_children():
			root.remove_child(leftover)
			leftover.free()
		await physics_frame

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
