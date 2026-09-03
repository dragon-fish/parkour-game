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

func test_nothing_ever_poses_the_players_own_skeleton() -> void:
	# ONE WRITER PER SKELETON, and for the Player that writer is the
	# AnimationTree the move machine drives. The opening films a stand-in
	# precisely so it never has to switch that off: an opening that reaches for
	# the real body has to silence an AnimationTree, a HeadLook modifier, the
	# clip-offset drivers and the spring bones, and the one it forgets is the
	# one on screen -- a twisted neck, or a body held in the crouch clip
	# through every move made afterwards. Both of those have shipped.
	var level: Node = await _loaded()
	var player: Player = level.get_node("Player")
	var tree: AnimationTree = player.get_node_or_null("BodyRoot/AnimationTree")
	if tree == null:
		pass_test("no body is mounted on this machine, so there is no skeleton to fight over")
		return
	assert_true(tree.active, "the opening switched the player's own animation tree off")
	await _click_through(level)
	await step(4)
	assert_true(tree.active, "the player's animation tree is not driving her body")
	var anim: AnimationPlayer = tree.get_node(tree.anim_player)
	assert_false(anim.is_playing(),
		"a clip is being played straight onto the player's skeleton, over the tree")

func test_the_opening_starts_flat_and_hands_the_palette_back() -> void:
	# THE MENU IS A FLAT PLATE AND THIS IS A LIT WORLD. Held side by side they
	# read as two different places -- a graduated sky over a mirror of a floor
	# against one near-white rectangle. The shot starts painted like the menu
	# and the level's own palette arrives with control.
	#
	# Only the RELATIONSHIP is asserted: flat and unreflective while held, the
	# authored values back afterwards. The colours themselves are the author's.
	var level: Node = await _loaded()
	var world: WorldEnvironment = level.get_node("WorldEnvironment")
	var sky: ProceduralSkyMaterial = world.environment.sky.sky_material
	var floor_material: ShaderMaterial = level.get_node("Plain/Mesh").material_override
	assert_eq(sky.sky_top_color, sky.sky_horizon_color,
		"the held shot has a horizon in its sky, so it is not the menu's flat plate")
	assert_almost_eq(float(floor_material.get_shader_parameter("metallic_amount")), 0.0, 0.001,
		"the held shot still mirrors, which is what reads as a different place")

	var authored_top: Color = sky.sky_top_color
	var authored_metallic: float = float(floor_material.get_shader_parameter("metallic_amount"))
	level.get_node("TutorialIntro")._hand_over()
	await step(2)
	assert_ne(sky.sky_top_color, authored_top,
		"the sky never came back, so the level is stuck wearing the opening")
	assert_gt(float(floor_material.get_shader_parameter("metallic_amount")), authored_metallic,
		"the floor never got its sheen back")

func test_the_opening_does_not_repaint_the_shared_material() -> void:
	# materials/acrylic_void.tres is shared with the debug plain. Painting it
	# in place would follow every other scene that loads it for the rest of the
	# session, and the symptom appears somewhere this level never touched.
	# WHILE THE SHOT IS STILL HELD. Handing over paints the authored values
	# back, so afterwards a polluted shared material and a clean one hold the
	# same numbers and nothing can tell them apart -- the damage is only
	# visible during the shot, which is also the whole time it would be doing
	# it to every other scene.
	var before: float = float(load("res://materials/acrylic_void.tres")
		.get_shader_parameter("metallic_amount"))
	var level: Node = await _loaded()
	assert_almost_eq(float(load("res://materials/acrylic_void.tres")
		.get_shader_parameter("metallic_amount")), before, 0.001,
		"the opening painted the shared material rather than its own copy")

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
##
## THE INVITATION IS FORCED, NOT WAITED FOR. The opening ignores a press made
## before 「点击任意处开始」 is on screen -- the same gate the main menu has --
## and the half second it takes to arrive is the beat's own pacing, not any of
## these tests' subject.
func _click_through(level: Node) -> TutorialIntro:
	var intro: TutorialIntro = level.get_node("TutorialIntro")
	if intro._plate != null:
		intro._plate.prompt_shown = true
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

func test_the_body_in_the_void_is_a_flat_red_silhouette() -> void:
	# She is the same figure the front door holds on its opening plate, and the
	# same red. A body that came up lit is a different character in the same
	# level, and nothing errors -- the level is simply wrong to look at.
	#
	# TOLERANT OF A MACHINE WITH NO MODEL: body_scene is optional here by
	# design, and a checkout without the private asset submodule has nothing
	# mounted to paint.
	var level: Node = await _loaded()
	var body_root: Node = level.get_node("Player").get_node_or_null("BodyRoot")
	var meshes: Array[Node] = []
	if body_root != null:
		meshes = body_root.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		pass_test("no body is mounted on this machine, so there is nothing to paint")
		return
	for mesh in meshes:
		var override: Material = (mesh as MeshInstance3D).material_override
		assert_true(override is StandardMaterial3D,
			"%s kept its own material, so it is not a silhouette" % mesh.name)
		if not (override is StandardMaterial3D):
			continue
		var flat := override as StandardMaterial3D
		assert_eq(flat.albedo_color, MeTheme.BRAND_RED,
			"%s is not the brand red the front door uses" % mesh.name)
		assert_eq(flat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
			"%s is lit, so the void has a light direction in it" % mesh.name)

func test_exactly_one_body_is_on_screen_and_the_stand_in_leaves_with_the_shot() -> void:
	# THE WHOLE TRICK IS THAT NOBODY SEES THE SWAP. Two red silhouettes in the
	# same spot is one figure with a doubled outline; none at all is an empty
	# void with a camera pointed at it. And a stand-in left behind afterwards is
	# a second body standing exactly where the player is about to run from.
	var level: Node = await _loaded()
	var player: Player = level.get_node("Player")
	var intro: TutorialIntro = level.get_node("TutorialIntro")
	var body_root: Node3D = player.get_node_or_null("BodyRoot") as Node3D
	if intro.performer == null:
		pass_test("no body is mounted on this machine, so there is no stand-in to swap")
		return
	assert_true(intro.performer.visible, "the stand-in is not on screen during her own shot")
	assert_false(body_root.visible,
		"the player's body is drawn behind the stand-in, so the figure is doubled")

	await _click_through(level)
	await step(3)
	assert_true(body_root.visible, "control arrived and the body it belongs to is invisible")
	assert_false(is_instance_valid(intro.performer),
		"the stand-in is still standing where the player has to run from")

func test_the_stand_in_carries_nothing_that_writes_its_bones() -> void:
	# The reason there is a stand-in at all. It is a bare model with its own
	# AnimationPlayer: give it an AnimationTree or a skeleton modifier and it
	# becomes the thing it was built to replace, and the deformity that started
	# this comes back with it.
	var level: Node = await _loaded()
	var intro: TutorialIntro = level.get_node("TutorialIntro")
	if intro.performer == null:
		pass_test("no body is mounted on this machine, so there is no stand-in to inspect")
		return
	# NAMED, not "no SkeletonModifier3D anywhere": a model ships its own spring
	# bones and those are welcome -- they are jiggle, not a pose. What must not
	# be here is anything Player._attach_body() adds, because the only way one
	# of these gets in is the stand-in being built down the Player's own path.
	for writer in ["AnimationTree", "CharacterAnimator", "HeadLook", "BalanceLean", "HandIK"]:
		assert_eq(intro.performer.find_children("*", writer, true, false).size(), 0,
			"the stand-in carries a %s, so something other than its own clip writes its bones" % writer)
	assert_not_null(intro.performer.anim_player,
		"the stand-in has nothing driving it at all")

func test_the_opening_holds_the_same_plate_the_front_door_does() -> void:
	# 和正常主菜单的逻辑完全一样: up to the press, a player who has never
	# finished the tutorial must see what a returning player sees -- the mark
	# and 「点击任意处开始」, in the same places on the same beat. Sharing the
	# class IS the parity; nothing here asserts a fraction or a duration,
	# because there is now only one place any of them can be changed.
	var level: Node = await _loaded()
	var intro: TutorialIntro = level.get_node("TutorialIntro")
	var plate: MeOpeningPlate = intro._plate
	assert_not_null(plate, "the tutorial opens with no plate, so there is no mark and no invitation")
	if plate == null:
		return
	# CHECKED BEFORE ANYTHING IS READ OFF IT: a plate that was built but never
	# parented has no children -- they are made in its _ready() -- and reaching
	# for logo.texture there is a runtime error, which this runner does not
	# count as a failure (see .claude/skills/reading-past-a-green-suite).
	assert_true(plate.is_visible_in_tree(), "the plate is built but not on screen")
	if not plate.is_inside_tree():
		return
	assert_not_null(plate.logo.texture, "the plate is holding no mark")

	await _click_through(level)
	await step(3)
	assert_false(is_instance_valid(plate),
		"the mark and the invitation are still over a level the player is driving")

func test_the_held_opening_uses_the_menu_background_behind_the_body() -> void:
	var level: Node = await _loaded()
	var intro: TutorialIntro = level.get_node("TutorialIntro")
	assert_not_null(intro._chladni,
		"the tutorial opening is missing the main menu's Chladni field")
	assert_not_null(intro._opening_background,
		"the tutorial opening has no warm-white canvas behind the body")
	assert_eq(level.get_node("WorldEnvironment").environment.background_mode,
		Environment.BG_CANVAS,
		"the tutorial draws its opening canvas over the body instead of behind it")
	assert_lt(intro._backdrop_layer.layer, 0,
		"the opening canvas is on a foreground layer and covers the 3D body")
	if intro.performer != null and intro.performer.anim_player != null:
		assert_true(intro.performer.anim_player.is_playing(),
			"the tutorial crouch pose is frozen instead of looping")

	intro._plate.prompt_shown = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	intro._unhandled_input(key)
	await step(1)
	assert_true(is_instance_valid(intro._backdrop_layer),
		"the warm-white opening background disappears on the click frame")
	for i in 200:
		await step(1)
		if not intro.is_holding():
			break
	assert_eq(level.get_node("WorldEnvironment").environment.background_mode,
		Environment.BG_SKY,
		"the authored tutorial sky did not return after the opening press")
