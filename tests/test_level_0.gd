extends ParkourTest

# The tutorial level as a whole. Everything asserted here is a wiring fact
# whose failure is SILENT: an unresolved export or a lesson table that did not
# survive the scene file both leave a level that simply sits there.

const LEVEL := "res://scenes/levels/level_0/level_0.tscn"

var _level: Node

func after_each() -> void:
	if is_instance_valid(_level):
		_level.queue_free()
	_level = null

func _loaded() -> Node:
	var level: Node = load(LEVEL).instantiate()
	add_child_autofree(level)
	await step(2)
	_level = level
	return level

func test_the_level_starts_the_camera_behind_the_body() -> void:
	# The tutorial hands over control in third person. A level that came up in
	# first person would hand the player a view he never chose and no reason
	# to know V exists.
	var level: Node = await _loaded()
	assert_true(level.start_in_third_person,
		"level_0 does not declare start_in_third_person")
	assert_true(level.player.camera_rig.third_person,
		"level_0 did not actually start behind the body")

func test_only_the_opening_row_teaches_without_a_scene() -> void:
	# THE OPENING ROW IS THE ONLY LEGITIMATE null. It is an empty plain on
	# purpose. Every other row's scene comes from load(), which returns null
	# for a path that is not there -- so a single mistyped filename bakes a
	# level that quietly teaches one lesson fewer, and looks exactly like the
	# row that is meant to be empty.
	var level: Node = await _loaded()
	var director: TutorialDirector = level.get_node("TutorialDirector")
	for at in range(1, director.lessons.size()):
		assert_not_null(director.lessons[at].get(&"scene"),
			"lesson row %d has no scene, so its path did not load" % at)

func test_the_loop_actually_runs_in_the_assembled_scene() -> void:
	# THE ONE TEST THAT USES THE SCENE'S OWN WIRING ORDER. Every other test of
	# the director builds the player first and hands it over already set up.
	# A real level does the opposite: a child's _ready() runs before its
	# parent's, so the director is ready before Arena._ready() has called
	# player.setup() and move_manager does not exist yet. A director that hooks
	# up in _ready() connects to nothing, and the whole tutorial sits still
	# while every hand-wired test still passes.
	var level: Node = await _loaded()
	var director: TutorialDirector = level.get_node("TutorialDirector")
	var player: Player = level.get_node("Player")
	assert_not_null(player.move_manager, "the player was never set up")
	var before: int = director.index
	player.move_manager.move_changed.emit(&"", director.lessons[before].get(&"teaches", &""))
	await step(2)
	assert_eq(director.index, before + 1,
		"performing the taught move did not advance the lesson in the real scene")
	assert_gt(director.live_count(), 0,
		"advancing built no geometry, so the player is left on an empty plain")

func test_the_lesson_table_survived_the_scene_file() -> void:
	# An exported Array[Dictionary] that does not round-trip through .tscn
	# leaves the director with nothing to teach. The level then never finishes,
	# the tower never rises, and no error is printed anywhere.
	var level: Node = await _loaded()
	var director: TutorialDirector = level.get_node("TutorialDirector")
	assert_false(director.lessons.is_empty(),
		"the exported lesson table did not survive the scene file")
	for row in director.lessons:
		assert_true(row.has(&"teaches"), "a lesson row lost its teaches field")
		var scene: PackedScene = row.get(&"scene")
		if scene == null:
			continue
		var content := LessonContent.take(scene)
		assert_not_null(content, "a lesson row points at a scene with no Content")
		content.free()

func test_level_zero_found_every_node_it_drives() -> void:
	# Node-path exports that point into an INSTANCED sub-scene are the fragile
	# ones here. Any of them coming back null makes the chain stop at that
	# link, with the level still perfectly playable up to it.
	var level: Node = await _loaded()
	var chain: LevelZero = level.get_node("LevelZero")
	assert_not_null(chain.player, "LevelZero has no player")
	assert_not_null(chain.director, "LevelZero has no director")
	assert_not_null(chain.wrap, "LevelZero has no wrap")
	assert_not_null(chain.tower, "LevelZero has no tower")
	assert_not_null(chain.tower_checkpoint, "LevelZero has no base checkpoint")
	assert_not_null(chain.orb, "LevelZero has no orb")
	assert_not_null(chain.plain, "LevelZero has no plain")
	assert_not_null(chain.plain_mesh, "LevelZero has no plain mesh")
	assert_not_null(chain.plain_collision, "LevelZero has no plain collision")
	assert_not_null(chain.spawn_point, "LevelZero has no spawn point")

func test_the_level_opens_by_saying_its_three_lines() -> void:
	# LESSON 0 HAS NO GEOMETRY ON PURPOSE, so these lines are the only thing
	# there is once the player can move. An opening that was never built, or
	# built and never played, or played into a layer that is not the one on
	# screen, all leave the same thing: a blank white plain, nothing said,
	# nothing to look at, and the player guessing which key to press.
	#
	# AND THEY WAIT FOR CONTROL. Spent over the held opening shot they would be
	# gone by the time he could press anything -- the same three lines, and
	# useless.
	#
	# THE WORDING IS NOT ASSERTED -- it is content, and it is rewritten from the
	# key table anyway. What is asserted is that what reached the screen came
	# from this opening.
	var level: Node = await _loaded()
	var opening: TutorialOpening = level.get_node_or_null("TutorialOpening")
	assert_not_null(opening, "the generated level has no TutorialOpening")
	if opening == null:
		return
	assert_eq(opening.subtitle, level.player.subtitle,
		"the opening does not speak into the player's own subtitle layer")
	if opening.subtitle == null:
		return
	assert_eq(opening.subtitle.text(), "",
		"the opening spoke over the held shot, where nothing can be pressed")
	await _click_through(level)
	assert_true(opening.lines().has(opening.subtitle.text()),
		"control was handed over and the opening still said nothing")

# ---------------------------------------------------------------------------
# The opening shot. The level begins on a held close-up of the crouched body,
# and a click stands her up, brings the camera round behind her and hands over
# control -- all inside this one scene. Every failure below is silent: a level
# that hands over nothing looks like a level that has frozen, and one that
# hands over instantly looks like a level with no opening at all.
# ---------------------------------------------------------------------------

## Presses a key at the held shot and runs until the intro reports it is done.
func _click_through(level: Node) -> TutorialIntro:
	var intro: TutorialIntro = level.get_node("TutorialIntro")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	intro._unhandled_input(key)
	# Long enough for the whole rise at 60 Hz, with room over it. The intro
	# stops its own physics processing the moment it hands over, so the extra
	# frames cost nothing and no duration is pinned here.
	for i in 200:
		await step(1)
		if not intro.is_holding():
			break
	return intro

func test_the_level_holds_control_until_something_is_pressed() -> void:
	# The whole point of the opening: she is a picture until the player asks
	# for her. Unlocked here, the level starts with a body already drivable
	# under a camera parked off to one side, which reads as broken controls.
	var level: Node = await _loaded()
	var intro: TutorialIntro = level.get_node_or_null("TutorialIntro")
	assert_not_null(intro, "the generated level has no TutorialIntro")
	if intro == null:
		return
	assert_true(intro.is_holding(), "the opening shot was over before it began")
	assert_true(level.player.is_input_locked(),
		"the level handed over control before anything was pressed")

func test_a_press_hands_over_control_with_nothing_covering_the_screen() -> void:
	# THE REASON THIS WORK EXISTS. The old route from the crouched close-up to
	# the game was a scene swap under a white curtain; here the two are the same
	# scene, so a curtain or a scene change anywhere on this path is the defect
	# itself, not a detail. PauseUi is where both live: run_white_transition()
	# wakes that layer, and go_to_main_menu()/the level's own exit go through
	# its change-scene seam.
	var level: Node = await _loaded()
	var requested := [""]
	var previous: Callable = PauseUi._change_scene
	PauseUi._change_scene = func(path): requested[0] = path
	var intro: TutorialIntro = await _click_through(level)
	PauseUi._change_scene = previous

	assert_false(intro.is_holding(), "the press never handed control over")
	assert_false(level.player.is_input_locked(),
		"control was handed over and the body is still locked")
	assert_eq(requested[0], "", "the hand-over changed scene")
	assert_false(PauseUi.visible, "the hand-over pulled a curtain over itself")

func test_the_held_shot_is_beside_the_body_and_the_rise_lands_without_a_cut() -> void:
	# Three failures, one shot, because each alone leaves a plausible-looking
	# level: a shot that was never posed opens on the ordinary over-the-shoulder
	# view (so there is no opening at all), a rig that is never handed back
	# leaves the camera parked out to the side for the whole tutorial, and a
	# rise that ends anywhere other than the rig's own seat makes the frame
	# control arrives a CUT -- which is the exact thing this whole change exists
	# to remove.
	#
	# SIDES AND CONTINUITY, NOT DISTANCES. Where the lens sits is the author's
	# to retune.
	var level: Node = await _loaded()
	var player: Player = level.get_node("Player")
	var rig: CameraRig = player.camera_rig
	assert_true(rig.in_cinematic(), "the opening shot never took the camera")
	var held: Vector3 = player.to_local(rig.camera.global_position)
	assert_gt(absf(held.x), absf(held.z), "the held shot is not beside the body")

	await _click_through(level)
	assert_false(rig.in_cinematic(), "the camera was never handed back")
	var landed: Vector3 = player.to_local(rig.camera.global_position)
	await step(3)
	var settled: Vector3 = player.to_local(rig.camera.global_position)
	# A CUT IS METRES, NOT CENTIMETRES: the third-person seat alone is three of
	# them behind her, so anything that ends the rise in the wrong place lands
	# far outside this. What is left inside it is the head's own displacement,
	# which a cutscene pose does not carry and the rig adds back the moment it
	# has the camera again.
	assert_lt(landed.distance_to(settled), 0.15,
		"the camera jumped the frame control arrived")

func test_the_body_is_animating_again_once_control_arrives() -> void:
	# The shot drives the body's AnimationPlayer directly, which means switching
	# the AnimationTree off for the length of it. Left off, the body plays its
	# last clip forever and no move ever reaches the screen -- and the level is
	# otherwise completely playable, so nothing says why.
	var level: Node = await _loaded()
	var tree: AnimationTree = level.get_node("Player").get_node_or_null("BodyRoot/AnimationTree")
	if tree == null:
		pass_test("no body is mounted on this machine, so there is no tree to switch")
		return
	assert_false(tree.active, "the tree kept driving the body through the held shot")
	await _click_through(level)
	assert_true(tree.active, "the body was left frozen on the shot's last pose")

func test_the_director_and_the_wrap_both_have_the_body() -> void:
	# Both are wired by NodePath and both fail the same silent way: a director
	# with no player never hears a move happen, a wrap with no player never
	# wraps, and the level looks like a plain with nothing on it.
	var level: Node = await _loaded()
	assert_not_null((level.get_node("TutorialDirector") as TutorialDirector).player,
		"the director has no player, so no lesson can ever be passed")
	assert_not_null((level.get_node("TorusWrap") as TorusWrap).player,
		"the wrap has no player, so the plain has edges")

func test_the_tower_is_not_in_the_way_before_it_rises() -> void:
	# The lessons are taught on the ground the tower stands on. A tower that is
	# only hidden is an invisible wall in the middle of the teaching field.
	var level: Node = await _loaded()
	var tower: Node3D = level.get_node("Tower")
	assert_false(tower.visible, "the tower is visible before the lessons are done")

func test_the_plain_wears_a_shader_material() -> void:
	# LevelZero drives the floor's disappearance through shader uniforms
	# (base_color, dot_opacity, ...). A plain mesh with no ShaderMaterial, or
	# one wearing an ordinary StandardMaterial3D, makes the whole floor beat a
	# no-op: no error anywhere, the player just stands on a floor that never
	# leaves.
	var level: Node = await _loaded()
	var mesh: MeshInstance3D = level.get_node("LevelZero").plain_mesh
	assert_true(mesh.material_override is ShaderMaterial,
		"the plain's mesh is not wearing a ShaderMaterial")

func test_the_player_never_takes_a_black_curtain_death() -> void:
	# The standing rule for this level: every reset is a WHITE curtain, never
	# a death animation. rescue_below_hp at its default of 0.0 turns a fall
	# into the void -- reachable the instant the plain's collision goes away
	# -- into a black-curtain death.
	var level: Node = await _loaded()
	assert_gt(level.rescue_below_hp, 0.0,
		"rescue_below_hp is not above zero -- a fall becomes a death, not a rescue")

func test_the_spawn_point_is_wired() -> void:
	# Arena.reset_player() crashes if spawn_point is unwired and no checkpoint
	# is active -- exactly the state of the level the instant it loads, before
	# the tower checkpoint has ever been touched.
	var level: Node = await _loaded()
	assert_not_null(level.spawn_point, "level_0 has no spawn_point wired")
