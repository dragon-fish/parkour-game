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
