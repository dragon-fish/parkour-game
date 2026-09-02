extends ParkourTest

# Taking one lesson's content out of a scene that is also a playable level.
# What is asserted is the contract: the Content subtree arrives detached and
# alive, and nothing else in the file was ever brought to life.

## Builds a stand-in for a lesson scene: a root carrying arena.gd (as an
## inherited lesson scene would), a Content node, and a sibling that must be
## discarded.
func _lesson_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "Arena"
	root.set_script(load("res://scripts/level/arena.gd"))

	var content := Node3D.new()
	content.name = "Content"
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	content.add_child(wall)
	root.add_child(content)

	var scaffolding := Node3D.new()
	scaffolding.name = "Floor"
	root.add_child(scaffolding)

	content.owner = root
	wall.owner = root
	scaffolding.owner = root

	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "test setup: could not pack the stand-in")
	root.free()
	return packed

func test_it_returns_the_content_subtree() -> void:
	var content := LessonContent.take(_lesson_scene())
	assert_not_null(content, "no Content came back")
	assert_eq(content.name, &"Content", "something other than Content came back")
	assert_not_null(content.get_node_or_null("Wall"),
		"the content arrived without its own children")
	content.free()

func test_the_content_arrives_detached() -> void:
	# It has to be free to be reparented into the tutorial, so it must not
	# still belong to the scene it came out of.
	var content := LessonContent.take(_lesson_scene())
	assert_null(content.get_parent(), "the content is still parented to its scene")
	content.free()

func test_nothing_else_from_the_scene_survives() -> void:
	# The scaffolding a lesson carries so it can be played on its own -- floor,
	# light, player -- must not follow it into the tutorial. take() never adds
	# anything to a SceneTree, so a live-node-count comparison can't see a
	# leak either way -- OBJECT_NODE_COUNT only counts nodes inside a tree,
	# and the discarded half never is one. An orphan (alive, parented to
	# nothing) is the direct signal: it is exactly what "released" means here.
	# The leading step() lets an adjacent test's own frees land before the
	# baseline is read -- otherwise this test intermittently attributes a
	# neighbour's cleanup lag to LessonContent.
	await step(2)
	var before: int = _orphan_count()
	var content := LessonContent.take(_lesson_scene())
	content.free()
	await step(2)
	assert_eq(_orphan_count(), before,
		"the discarded half of the lesson scene was left alive as an orphan")

func test_a_scene_without_content_returns_null_instead_of_crashing() -> void:
	# A level author who has not added the node yet gets nothing, not a crash.
	var root := Node3D.new()
	root.name = "Arena"
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "test setup: could not pack")
	root.free()
	assert_null(LessonContent.take(packed), "a scene with no Content returned something")

func _orphan_count() -> int:
	return Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
