extends ParkourTest

# The game's first scene. It answers one question -- menu or tutorial -- and
# every way of getting that answer wrong is a launch that looks fine and goes
# to the wrong place: a first-time player dropped into a menu he has not earned,
# or a returning one trapped in a tutorial he already did.
#
# ProgressStore.path is redirected for the whole file so the suite never reads,
# writes or deletes the author's real progress.

var _test_progress_path: String
var _real_progress_path: String

func before_all() -> void:
	_test_progress_path = "user://progress_router_test_%d.cfg" % OS.get_process_id()
	_real_progress_path = ProgressStore.path
	ProgressStore.path = _test_progress_path

func after_all() -> void:
	_delete_progress_file()
	ProgressStore.path = _real_progress_path

func before_each() -> void:
	_delete_progress_file()
	ProgressStore.replay_requested = false

func after_each() -> void:
	_delete_progress_file()
	# Session-only and static, so unlike the file it survives a delete: left
	# true it would send every later test down the tutorial branch.
	ProgressStore.replay_requested = false

func _delete_progress_file() -> void:
	if FileAccess.file_exists(ProgressStore.path):
		DirAccess.remove_absolute(ProgressStore.path)

## Builds the router and reports where it routed this launch. The seam is
## installed BEFORE the node enters the tree: the decision is made in _ready(),
## and headless takes the synchronous path there and then.
func _routed_to() -> String:
	var router := BootRouter.new()
	var requested := [""]
	router._change_scene = func(path): requested[0] = path
	add_child_autofree(router)
	await step(1)
	return requested[0]

func test_a_launch_that_has_never_finished_the_tutorial_goes_to_the_tutorial() -> void:
	assert_eq(await _routed_to(), BootRouter.LEVEL_0_SCENE,
		"a first launch did not go into the tutorial")

func test_a_launch_that_has_finished_the_tutorial_goes_to_the_menu() -> void:
	ProgressStore.mark_tutorial_finished()
	assert_eq(await _routed_to(), BootRouter.MAIN_MENU_SCENE,
		"a returning player was sent back into the tutorial")

func test_an_armed_replay_beats_a_finished_tutorial() -> void:
	# 重玩新手教程 arms this and sends the game back to the front door. Read the
	# other way round -- finished first, armed second -- the row does nothing at
	# all and the player is returned to the menu he pressed it from.
	ProgressStore.mark_tutorial_finished()
	ProgressStore.replay_requested = true
	assert_eq(await _routed_to(), BootRouter.LEVEL_0_SCENE,
		"重玩新手教程 did not survive the trip through the front door")

func test_the_plate_is_on_screen_before_anything_is_loaded() -> void:
	# THE REASON THIS SCENE EXISTS IS THAT IT IS NEVER BLANK. A router that
	# builds nothing is a frame of empty grey while the target loads, which is
	# the one thing docs/seamless-loading.md forbids -- and it would look
	# exactly like a fast launch on the machine it was written on.
	var router := BootRouter.new()
	router._change_scene = func(_path): pass
	add_child_autofree(router)
	await step(1)
	var painted := false
	for child in router.get_children():
		if child is ColorRect and (child as ColorRect).color.a > 0.0:
			painted = true
	assert_true(painted, "the router shows an empty frame while the target loads")

func test_the_plate_fills_the_screen_it_is_a_child_of() -> void:
	# The trap in .claude/skills/godot-ui-layout-traps: a root Control gets the
	# viewport rect for free, so a plate built with anchors but no offsets looks
	# right as a scene root and collapses to a point the moment anything parents
	# it -- which is exactly what a test, and any future host, does.
	var host := Control.new()
	host.size = Vector2(640.0, 360.0)
	add_child_autofree(host)
	var router := BootRouter.new()
	router._change_scene = func(_path): pass
	host.add_child(router)
	await step(1)
	assert_gt(router.size.x, 0.0, "the router collapsed to a point inside its host")
	for child in router.get_children():
		if child is ColorRect:
			assert_gt((child as ColorRect).size.x, 0.0,
				"%s collapsed to a point inside the router" % child.name)

func test_the_way_out_of_a_level_re_asks_where_the_game_should_go() -> void:
	# 重玩新手教程 arms a replay and then leaves through PauseUi's own route.
	# Pointed straight at the main menu, that lands on a screen whose click
	# opens the menu -- the row silently does nothing, and the player is back
	# where he pressed it. What is asserted is the SHAPE of the destination and
	# never its path: moving the router is the author's business, and an
	# equality test on the string would only be a change detector.
	var packed: PackedScene = load(PauseUi.FRONT_DOOR_SCENE)
	assert_not_null(packed, "PauseUi's way out of a level does not load")
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	autofree(scene)
	assert_true(scene is BootRouter,
		"leaving a level lands somewhere that cannot decide where the game goes")

func test_the_game_starts_at_something_that_decides_where_to_go() -> void:
	# project.godot's main scene is the one path in the project nothing else
	# references, so nothing else can notice it pointing at the wrong door. Left
	# on the main menu, a first-ever launch opens a menu instead of the tutorial
	# and every test in this file still passes.
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed: PackedScene = load(main_scene) if ResourceLoader.exists(main_scene) else null
	assert_not_null(packed, "the project's main scene does not load: %s" % main_scene)
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	autofree(scene)
	assert_true(scene is BootRouter,
		"the game starts on a scene that cannot decide where the launch goes")
