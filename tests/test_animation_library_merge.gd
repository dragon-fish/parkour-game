extends ParkourTest

# A body that ships no locomotion can borrow it from an animation pack.
#
# VRM forces this: the format carries no animation at all by design, so an
# imported VRM's AnimationPlayer holds only blend-shape expressions -- blink,
# happy, aa -- and the body just stands there. The clips have to come from
# somewhere else, and Godot's import-time retargeting is what makes them
# portable: a pack imported against SkeletonProfileHumanoid has its tracks
# rewritten to address %GeneralSkeleton and profile bone names, which any other
# humanoid imported the same way answers to.
#
# Synthetic on both sides here. What is under test is the merge and the
# precedence, neither of which needs a real rig.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	return _world["player"]

## A Node3D with an AnimationPlayer carrying `clips`, packed so it can stand in
## for either a body or a library.
func _scene_with(clips: Array) -> PackedScene:
	var root := Node3D.new()
	root.name = "fake"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in clips:
		var animation := Animation.new()
		animation.length = 1.0
		# A track, so a merged clip is distinguishable from an empty one, and
		# one that RESOLVES: a real pack addresses %GeneralSkeleton:Hips, but
		# there is no skeleton in this fixture and AnimationMixer warns about
		# every track it cannot find. What is under test is the merge, not the
		# track path.
		animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(0, NodePath(".:visible"))
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	root.add_child(anim_player)
	anim_player.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _clips_on(player: Player) -> PackedStringArray:
	var anim_player := player.body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	return PackedStringArray() if anim_player == null else anim_player.get_animation_list()

func test_the_library_fills_a_body_that_has_nothing() -> void:
	var player: Player = await _player()
	player.body_animation_libraries = [_scene_with([&"Slide", &"ClimbUp_1m"])]
	player._attach_body(_scene_with([]))
	await step(1)
	var clips := _clips_on(player)
	assert_true(clips.has("Slide"), "the pack's Slide never reached the body")
	assert_true(clips.has("ClimbUp_1m"), "the pack's ClimbUp_1m never reached the body")

func test_the_body_keeps_its_own_clip_over_the_library_s() -> void:
	# THE PRECEDENCE THAT MATTERS. A body shipping its own `run` was animated by
	# its author; silently replacing it with a generic one is the opposite of
	# filling a gap.
	var player: Player = await _player()
	player.body_animation_libraries = [_scene_with([&"run"])]
	var own := _scene_with([&"run"])
	player._attach_body(own)
	await step(1)
	var anim_player := player.body.get_node("AnimationPlayer") as AnimationPlayer
	var body_run: Animation = anim_player.get_animation(&"run")
	# Identity is the only way to tell them apart: both are named `run`.
	assert_eq(body_run.get_track_count(), 1, "the body's own run was replaced")

func test_the_merged_clips_reach_the_state_machine() -> void:
	# Merging is pointless if _wire_body_animation() has already decided what
	# the body can do -- hence the merge running BEFORE it.
	var player: Player = await _player()
	player.body_animation_libraries = [_scene_with([&"Slide"])]
	player._attach_body(_scene_with([&"idle"]))
	await step(1)
	var animator: CharacterAnimator = \
		player.get_node("BodyRoot").get_node("CharacterAnimator")
	player.move_manager.start(Move.SLIDE)
	assert_eq(String(animator._target_animation()), "Slide", \
		"a slide asked for '%s' -- the merged clip is not in the graph" \
		% String(animator._target_animation()))

func test_no_library_is_a_silent_no_op() -> void:
	var player: Player = await _player()
	player.body_animation_libraries = []
	player._attach_body(_scene_with([&"idle"]))
	await step(1)
	assert_eq(_clips_on(player).size(), 1, "an absent library changed the body's clips")

func test_a_library_with_no_animation_player_does_not_crash() -> void:
	# Presentational, so it degrades: the same line _attach_body() takes for a
	# body that cannot be attached at all.
	var player: Player = await _player()
	var empty := Node3D.new()
	empty.name = "empty"
	var packed := PackedScene.new()
	packed.pack(empty)
	empty.free()
	player.body_animation_libraries = [packed]
	player._attach_body(_scene_with([&"idle"]))
	await step(1)
	assert_eq(_clips_on(player).size(), 1, "a library with nothing in it disturbed the body")

func test_several_libraries_merge_and_the_first_wins() -> void:
	# No single free pack covers a parkour game: one has the locomotion and the
	# roll, another the slide and the ledge climb. Both get merged, in order.
	var player: Player = await _player()
	player.body_animation_libraries = [
		_scene_with([&"Roll", &"Shared"]),
		_scene_with([&"Slide", &"Shared"]),
	]
	player._attach_body(_scene_with([]))
	await step(1)
	var clips := _clips_on(player)
	assert_true(clips.has("Roll"), "the first library's clip is missing")
	assert_true(clips.has("Slide"), "the second library's clip is missing")
	assert_true(clips.has("Shared"), "the name both libraries carry is missing entirely")
