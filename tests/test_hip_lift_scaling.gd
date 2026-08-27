extends ParkourTest

# A clip's own hip lift is SCALED to what the obstacle needs, not fixed.
#
# DO NOT use the clip's own unscaled hip curve as the lift: measured across
# the real pack, ClimbUp_2m rises 0.617 m above rest, SafetyVault 0.732,
# StepUp 0.226 -- each right only for the one wall its animator sized it
# against, and each one added to the capsule's own rise puts the hands
# 1.32 m out on a shorter obstacle.
#
# DO NOT pin the lift flat at 0 either: that is only right when the capsule
# alone provides all the clearance, and leaves several in-place clips too
# low for their obstacle.
#
# So the SHAPE of the clip's hip curve stays and the MAGNITUDE is rescaled
# per obstacle.

const TestWorld = preload("res://tests/world_fixture.gd")
const REST := Vector3(0.0, 0.99, 0.0)
const CLIP_PEAK := 1.2

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A body whose clips lift the hips CLIP_PEAK metres and put them back.
func _player_with_clips(clips: Array) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var root := Node3D.new()
	root.name = "fake_body"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	root.add_child(skeleton)
	skeleton.add_bone("Root")
	skeleton.add_bone("Hips")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis(), REST))
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	var library := AnimationLibrary.new()
	for clip in clips:
		var animation := Animation.new()
		animation.length = 1.0
		animation.step = 1.0 / 30.0
		var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, NodePath("Skeleton:Hips"))
		animation.position_track_insert_key(track, 0.0, REST)
		animation.position_track_insert_key(track, 0.5,
			REST + Vector3(0.0, CLIP_PEAK, 0.0))
		animation.position_track_insert_key(track, 1.0, REST)
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	for child in [skeleton, anim_player]:
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	player._attach_body(packed)
	await step(2)
	return player

func test_the_clip_keeps_its_own_hip_curve() -> void:
	# NOT FLATTENED. DO NOT rewrite the Hips track to a single key at rest:
	# that destroys the curve's shape, leaving nothing for
	# clip_lift_kept_for() to scale.
	var player: Player = await _player_with_clips([&"StepUp"])
	var anim_player: AnimationPlayer = player.body.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	var animation: Animation = anim_player.get_animation("StepUp")
	for i in animation.get_track_count():
		if animation.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		assert_eq(animation.track_get_key_count(i), 3,
			"the animator's hip curve was rewritten rather than measured")
		return
	assert_true(false, "the hips track went missing")

func test_the_peak_is_measured_for_a_scripted_clip() -> void:
	var player: Player = await _player_with_clips([&"StepUp"])
	assert_almost_eq(float(player.body_clip_hip_peaks.get(&"StepUp", 0.0)),
		CLIP_PEAK, 0.001, "the clip's own peak was not measured")

func test_a_clip_nothing_scripted_plays_is_not_measured() -> void:
	# The pair. Jump_Start's hips rise because that IS the jump; nothing about it
	# is a scripted move's clearance to be scaled.
	var player: Player = await _player_with_clips([&"Jump_Start"])
	assert_false(player.body_clip_hip_peaks.has(&"Jump_Start"),
		"a clip no scripted move plays was measured as if it were one")

func test_the_wanted_clearance_becomes_a_fraction_of_the_clip() -> void:
	var player: Player = await _player_with_clips([&"StepUp"])
	assert_almost_eq(player.clip_lift_kept_for(&"StepUp", 0.6), 0.5, 0.001,
		"half of the clip's own lift was not half")
	# CLAMPED AT BOTH ENDS. Asking for more than the clip has cannot invent
	# it, and a derivation that comes back negative means a low obstacle
	# wanting no rise at all, not an inverted one.
	assert_eq(player.clip_lift_kept_for(&"StepUp", 5.0), 1.0,
		"asking for more than the clip has stretched it")
	assert_eq(player.clip_lift_kept_for(&"StepUp", -1.0), 0.0,
		"a negative clearance pushed the body down")

func test_a_clip_that_was_never_measured_keeps_nothing() -> void:
	# Silent degradation, the same stance as everywhere else in the body
	# pipeline: an unknown clip gets the old flat behaviour rather than an error.
	var player: Player = await _player_with_clips([&"StepUp"])
	assert_eq(player.clip_lift_kept_for(&"NotAClip", 0.5), 0.0,
		"an unmeasured clip was given a fraction of a peak it does not have")
