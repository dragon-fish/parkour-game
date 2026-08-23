extends ParkourTest

# The hips are held still for the clips a scripted move plays, and only those.
#
# THE OWNER: "目的就是让动画在默认没K帧的情况下盆骨始终与胶囊的中心在一个位置...不然我
# 得同时兼顾两个都在做运动的坐标系，我这是在调和双星系统."
#
# It has to be a PIN and not the subtraction of a travel component, which was the
# first thing tried. Measured on the real pack, first key to last, ClimbUp_2m's
# hips move (-0.00, +0.09, +0.00) and StepUp's, SafetyVault's and ClimbUp_1m's do
# not move at all -- there is no net travel to take out. What they have is SWING:
# ClimbUp_2m covers 1.20 m of Y inside the clip and comes back. That is the
# second body in the two-body problem and it is bigger than the capsule's travel.
#
# Synthetic body rather than the real .glb: the packs are not tracked, and a test
# that skips itself on a clean checkout is not a test.

const TestWorld = preload("res://tests/world_fixture.gd")
const REST := Vector3(0.0, 0.99, 0.0)

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A body with a Hips bone, and clips whose hips swing through it.
func _body(clips: Array) -> PackedScene:
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
		# A swing, not a travel: out and back, exactly the shape the real climb
		# clips have.
		animation.position_track_insert_key(track, 0.0, REST)
		animation.position_track_insert_key(track, 0.5, REST + Vector3(0.0, 1.2, 0.0))
		animation.position_track_insert_key(track, 1.0, REST)
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	for child in [skeleton, anim_player]:
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _hips_track(player: Player, clip: StringName) -> Array:
	var anim_player: AnimationPlayer = player.body.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	var animation: Animation = anim_player.get_animation(String(clip))
	for i in animation.get_track_count():
		if animation.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if String(animation.track_get_path(i).get_concatenated_subnames()) != "Hips":
			continue
		var values: Array = []
		for k in animation.track_get_key_count(i):
			values.append(animation.track_get_key_value(i, k))
		return values
	return []

func _player_with(clips: Array) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player._attach_body(_body(clips))
	await step(2)
	return player

func test_a_scripted_move_clip_has_its_hips_held_at_rest() -> void:
	var player: Player = await _player_with([&"StepUp"])
	var values: Array = _hips_track(player, &"StepUp")
	assert_eq(values.size(), 1,
		"the hips still have a curve, so two things are moving on the same axis")
	assert_almost_eq(float((values[0] as Vector3).y), REST.y, 0.001,
		"the hips were pinned somewhere other than the rest pose")

func test_a_clip_nothing_scripted_plays_keeps_its_own_motion() -> void:
	# ⚠️ THE PAIR, and the one that stops this being a blunt instrument.
	# Jump_Start is a fallback on several of the vault branches, but it is also
	# the JUMP's own clip, where the capsule is ballistic and the hips' rise IS
	# the jump. Pinning it would delete the jump.
	var player: Player = await _player_with([&"Jump_Start"])
	var values: Array = _hips_track(player, &"Jump_Start")
	assert_eq(values.size(), 3, "an unpinned clip lost its hips curve")
	assert_gt(float((values[1] as Vector3).y), REST.y + 1.0,
		"the swing of an unpinned clip was flattened")

func test_the_hips_keep_their_rotation() -> void:
	# POSITION ONLY. Lean, twist and weight shift are performance; this is only
	# trying to stop two things owning the same axis.
	var player: Player = await _player_with([&"StepUp"])
	var anim_player: AnimationPlayer = player.body.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	var animation: Animation = anim_player.get_animation("StepUp")
	var positions := 0
	for i in animation.get_track_count():
		if animation.track_get_type(i) == Animation.TYPE_POSITION_3D:
			positions += 1
	assert_eq(positions, 1, "the hips position track was removed rather than pinned")
