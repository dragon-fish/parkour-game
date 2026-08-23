extends ParkourTest

# The visible body can be nudged per CLIP, because the mount can only ever be
# right for one pose.
#
# The mount places a standing body against the capsule. A pack's clips are
# authored around their own idea of where the ground, the wall or the ledge is,
# and the mismatch shows -- the owner's report on SafetyVault was that the hands
# were completely in mid-air.
#
# Two invariants here, and both are things that were nearly broken while this
# was written rather than things that seemed worth asserting afterwards.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A player with a real attached body, built at runtime so this depends on no
## untracked model.
func _player_with_body(mount_scale: float = 1.0) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var root := Node3D.new()
	root.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in [&"Idle", &"Sprint", &"SafetyVault"]:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	root.add_child(anim_player)
	# PackedScene.pack() only keeps children that declare an owner.
	anim_player.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	player.body_mount_scale = mount_scale
	player._attach_body(packed)
	return player

# --- the mount is captured, not recomputed ------------------------------------

func test_crouching_does_not_move_the_body() -> void:
	# THE ONE THAT WAS NEARLY BROKEN. body_mount_transform() derives its height
	# from current_capsule_height(), which shrinks for a crouch or a slide, and
	# the first draft of the per-clip offset recomputed it every tick. The body
	# must NOT move when the capsule does: the crouch is shown by the animation,
	# not by lowering the model. _attach_body() captures the transform once, and
	# this is what says so.
	var player: Player = await _player_with_body()
	var before: Vector3 = player.body.position
	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	await step(5)
	assert_almost_eq(player.body.position.distance_to(before), 0.0, 0.0001,
		"the body sank %.3f m when the capsule shrank"
		% player.body.position.distance_to(before))

# --- the offset is in BodyRoot's space, unscaled --------------------------------

func test_the_offset_is_not_multiplied_by_the_model_scale() -> void:
	# Otherwise nudging by 0.1 on a body scaled 1.22 moves it 0.122, and every
	# number typed into the profile means something slightly different for every
	# model. The tuner that produces these values counts in metres.
	for scale in [1.0, 1.22, 2.0]:
		var player: Player = await _player_with_body(scale)
		var before: Vector3 = player.body.position
		player.set_clip_offset_immediately(Vector3(0.0, 0.0, -0.1), Vector3.ZERO)
		var moved: float = player.body.position.z - before.z
		assert_almost_eq(moved, -0.1, 0.0001,
			"at model scale %.2f a 0.1 m nudge moved the body %.4f m" % [scale, moved])
		after_each()

func test_the_offset_rotates_about_the_model_origin() -> void:
	# Its feet, which is where the mount has already put it -- so a yaw does not
	# also translate the body. The vault is why this matters: the pack's clip
	# plants the RIGHT hand where this project's camera was built for the left,
	# and turning the body is the cheap half of the answer.
	var player: Player = await _player_with_body()
	var before: Vector3 = player.body.position
	player.set_clip_offset_immediately(Vector3.ZERO, Vector3(0.0, 90.0, 0.0))
	assert_almost_eq(player.body.position.distance_to(before), 0.0, 0.0001,
		"a pure rotation also moved the body")
	assert_almost_eq(absf(player.body.rotation.y), PI * 0.5, 0.001,
		"the body turned %.1f degrees instead of 90" % rad_to_deg(player.body.rotation.y))

# --- the table drives it --------------------------------------------------------

func test_the_clip_the_animator_is_playing_picks_the_offset() -> void:
	var player: Player = await _player_with_body()
	player.body_clip_offsets = {&"Idle": [Vector3(0.0, 0.0, -0.25), Vector3.ZERO]}
	# Long enough for the ease to arrive; it runs on body_animation_blend_time.
	await step(60)
	assert_almost_eq(player.body.position.z, player._body_mount.origin.z - 0.25, 0.005,
		"the body never eased to the offset its clip asked for")

func test_a_malformed_entry_is_ignored_rather_than_fatal() -> void:
	# These are hand-pasted out of a debug tool's console output. A body standing
	# in the wrong place is a better failure than a crash, and the alternative is
	# a typo taking the whole game down.
	var player: Player = await _player_with_body()
	player.body_clip_offsets = {&"Idle": "not a transform at all"}
	await step(5)
	assert_eq(player.clip_offset_for(&"Idle"), [], "a malformed entry was accepted")
	assert_almost_eq(player.body.position.distance_to(player._body_mount.origin), 0.0, 0.0001,
		"a malformed entry moved the body somewhere")

# --- the eye does not follow the correction -------------------------------------

func test_lowering_the_body_does_not_lower_the_camera() -> void:
	# ✅ THE OWNER'S REPORT: "I lowered one to fix third person and the
	# first-person camera went straight into the ground." In first person the eye
	# is dragged along by the head bone, so a correction meant to plant the
	# MODEL's hands moves the VIEW by the same amount -- and a few centimetres of
	# down is the floor.
	#
	# A clip offset says where the model should sit relative to the world. It is
	# not a statement about where the player is looking from, and moving the eye
	# deliberately has its own knobs.
	var player: Player = await _player_with_body()
	# A head to follow, placed like a real one: the fixture's body has no
	# skeleton, so stand in a node at roughly neck height.
	var head := Node3D.new()
	head.name = "FakeHead"
	player.body.add_child(head)
	head.position = Vector3(0.0, 1.5, 0.0)
	player.head_node = head
	player.head_rest_local = player.to_local(head.global_position)
	var rest: Vector3 = player._camera_head_offset()

	player.set_clip_offset_immediately(Vector3(0.0, -0.30, 0.0), Vector3.ZERO)
	var after: Vector3 = player._camera_head_offset()
	assert_almost_eq(after.distance_to(rest), 0.0, 0.001,
		"a 0.30 m drop moved the eye by %.3f m" % after.distance_to(rest))
	# And the MODEL did move -- otherwise this passes because nothing happened.
	assert_almost_eq(player.body.position.y, player._body_mount.origin.y - 0.30, 0.0001,
		"the body did not move either, so the test proves nothing")

# --- offsets that change over the clip --------------------------------------

func test_a_keyed_curve_is_read_between_its_keys() -> void:
	# ✅ THE OWNER, on ClimbUp_2m against the mantle's own path: "这个动画角色的脚
	# 中途是有悬空的，可能得按时间轴把它的 Z 压一下."
	#
	# ⚠️ A DIFFERENT TOOL FROM THE STATIC OFFSET ABOVE, not a replacement. That
	# one says "this clip sits 8 cm too far forward" -- one number for the whole
	# clip, which is what a mount mismatch is. This one says "at 40% through the
	# feet are floating", and no single number can fix that, because the error is
	# not constant.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"t": 0.0, "pos": Vector3.ZERO, "rot": Vector3.ZERO},
		{"t": 1.0, "pos": Vector3(0.0, 1.0, 0.0), "rot": Vector3.ZERO},
	]}
	var half: Array = player.clip_curve_at(&"Idle", 0.5)
	assert_false(half.is_empty(), "a keyed curve returned nothing mid-way")
	assert_almost_eq(float(half[0].y), 0.5, 0.001,
		"halfway between 0 and 1 came out as %.3f" % half[0].y)

func test_a_keyed_curve_holds_flat_outside_its_keys() -> void:
	# Flat rather than extrapolated, which is what a hand-keyed curve wants: the
	# author sees exactly the shape they typed, with nothing inventing overshoot
	# past the ends.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"t": 0.25, "pos": Vector3(0.0, 2.0, 0.0), "rot": Vector3.ZERO},
		{"t": 0.75, "pos": Vector3(0.0, 4.0, 0.0), "rot": Vector3.ZERO},
	]}
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.0)[0].y), 2.0, 0.001,
		"before the first key the curve did not hold")
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 1.0)[0].y), 4.0, 0.001,
		"after the last key the curve did not hold")

func test_a_clip_with_no_curve_is_unaffected() -> void:
	# The pair, and the thing most at risk: this rides on the same transform the
	# static offset uses, so a curve lookup that returned something for every
	# clip would move every body in the game.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Sprint": [
		{"t": 0.0, "pos": Vector3(0.0, 9.0, 0.0), "rot": Vector3.ZERO}]}
	assert_eq(player.clip_curve_at(&"Idle", 0.5), [],
		"a clip with no curve of its own picked one up")
