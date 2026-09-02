extends ParkourTest

# The tutorial's lesson scenes. Two conventions are asserted and both are
# structural; the geometry's SIZES are the author's to tune and are asserted
# nowhere.

const LESSONS := [
	"res://scenes/levels/level_0/lesson_vault.tscn",
	"res://scenes/levels/level_0/lesson_slide.tscn",
	"res://scenes/levels/level_0/lesson_wall_run.tscn",
	"res://scenes/levels/level_0/lesson_grab.tscn",
]

func test_every_lesson_hands_over_a_content_subtree() -> void:
	# Geometry that escaped Content contributes NOTHING to the tutorial and
	# does so silently -- the lesson simply never appears in front of the
	# player, and the level sits there waiting for a move he cannot make.
	for path in LESSONS:
		assert_true(ResourceLoader.exists(path), "missing lesson scene: %s" % path)
		var content := LessonContent.take(load(path))
		assert_not_null(content, "%s has no Content node" % path)
		assert_gt(content.get_child_count(), 0, "%s has an empty Content node" % path)
		content.free()

## Everything a lesson scene is allowed to have beside its Content: the
## scaffolding that exists so the author can open the file and run around in
## it. LessonContent.take() throws all of it away.
const SCAFFOLDING := ["Sun", "WorldEnvironment", "SpawnPoint", "Floor", "Player", "Content"]

func test_no_lesson_geometry_sits_outside_content() -> void:
	# A BLOCK THAT ESCAPES Content IS INVISIBLE IN THE TUTORIAL, and silently
	# so. Checking that Content is non-empty does not catch it: as long as one
	# block stays behind, the scene still looks populated while the escaped one
	# is thrown away with the scaffolding.
	#
	# Named from the OUTSIDE for that reason -- listing the blocks that must be
	# present would pin what a lesson is made of, which is the author's to
	# change. What is fixed is what may stand beside them.
	for path in LESSONS:
		var whole: Node = load(path).instantiate()
		for child in whole.get_children():
			assert_true(SCAFFOLDING.has(child.name),
				"%s: '%s' stands outside Content, so the tutorial never shows it" % [path, child.name])
		whole.free()

func test_every_lesson_can_be_opened_and_played_on_its_own() -> void:
	# The whole reason a lesson is its own file: the author shapes the geometry
	# by running around in it. A scene missing its scaffolding cannot be opened
	# for that, and the loss shows up as "why does nothing happen when I press
	# play" rather than as an error.
	for path in LESSONS:
		var whole: Node = load(path).instantiate()
		assert_not_null(whole.get_node_or_null("Player"),
			"%s has no Player, so it cannot be played on its own" % path)
		assert_not_null(whole.get_node_or_null("SpawnPoint"),
			"%s has no SpawnPoint, so Arena.reset_player() would crash in it" % path)
		assert_not_null(whole.get_node_or_null("Floor"),
			"%s has no floor to stand on" % path)
		whole.free()

func test_every_lesson_block_is_solid_and_made_of_cubes() -> void:
	# Two failures at once, both silent: geometry with no collision is scenery
	# the player runs through, and a block with no swarm falls back to the
	# alpha fade in a level where every other block comes apart.
	for path in LESSONS:
		var content := LessonContent.take(load(path))
		for body in content.find_children("*", "StaticBody3D", true, false):
			assert_gt(body.find_children("*", "CollisionShape3D", true, false).size(), 0,
				"%s: block %s has no collision" % [path, body.name])
			assert_gt(body.find_children("*", "CubeSwarm", true, false).size(), 0,
				"%s: block %s has no CubeSwarm" % [path, body.name])
		content.free()
