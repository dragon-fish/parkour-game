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
	player.active_obstacle = Vector2(1.2, 0.4)
	# KEYED AT 0.1 AND 0.9, NOT 0 AND 1, because the ends are not keyable any
	# more -- see the zero-ends rule at the bottom of this file. Halfway between
	# them is still halfway, which is what this test is about.
	player.body_clip_curves = {&"Idle": [{"h": 1.2, "w": 0.4, "keys": [
		{"t": 0.1, "pos": Vector3.ZERO, "rot": Vector3.ZERO},
		{"t": 0.9, "pos": Vector3(0.0, 1.0, 0.0), "rot": Vector3.ZERO},
	]}]}
	var half: Array = player.clip_curve_at(&"Idle", 0.5)
	assert_false(half.is_empty(), "a keyed curve returned nothing mid-way")
	assert_almost_eq(float(half[0].y), 0.5, 0.001,
		"halfway between 0 and 1 came out as %.3f" % half[0].y)

func test_a_keyed_curve_runs_back_to_zero_past_its_own_keys() -> void:
	# THIS TEST USED TO REQUIRE THE OPPOSITE. It held that the curve stayed FLAT
	# outside its keys -- 2.0 all the way back to t = 0 -- on the grounds that an
	# author should see exactly the shape they typed with nothing extrapolated.
	# That reasoning was about the SHAPE and ignored the JOIN: flat-to-the-start
	# means the body is already 2 m displaced on the tick the move begins, and
	# there is nothing before the move to have displaced it, so it teleports.
	#
	# What the author typed is still exactly what they get between their own
	# keys. Outside them the curve goes home. See the zero-ends rule below.
	var player: Player = await _player_with_body()
	player.active_obstacle = Vector2(1.2, 0.4)
	player.body_clip_curves = {&"Idle": [{"h": 1.2, "w": 0.4, "keys": [
		{"t": 0.25, "pos": Vector3(0.0, 2.0, 0.0), "rot": Vector3.ZERO},
		{"t": 0.75, "pos": Vector3(0.0, 4.0, 0.0), "rot": Vector3.ZERO},
	]}]}
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.0)[0].y), 0.0, 0.001,
		"the move began with the body already displaced")
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 1.0)[0].y), 0.0, 0.001,
		"the move ended with the body still displaced")
	# Between the keys, untouched: halfway from 2 to 4.
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 3.0, 0.001,
		"the hand-keyed middle was altered by the pinning")
	# And still nothing invented past them -- the run home is a straight line to
	# zero, not an overshoot.
	assert_lt(float(player.clip_curve_at(&"Idle", 0.875)[0].y), 4.0,
		"the curve overshot its last key on the way back to zero")

func test_a_clip_with_no_curve_is_unaffected() -> void:
	# The pair, and the thing most at risk: this rides on the same transform the
	# static offset uses, so a curve lookup that returned something for every
	# clip would move every body in the game.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Sprint": [{"h": 1.2, "w": 0.4, "keys": [
		{"t": 0.0, "pos": Vector3(0.0, 9.0, 0.0), "rot": Vector3.ZERO}]}]}
	assert_eq(player.clip_curve_at(&"Idle", 0.5), [],
		"a clip with no curve of its own picked one up")

func test_the_nearest_obstacle_row_wins() -> void:
	# ✅ THE OWNER: "我保存的数据会对应每一种组合，实际游戏场景中总是寻找最接近的那一组
	# 偏移量去应用." The grid samples a continuous space, so nothing in a level ever
	# lands on a grid point and every lookup is a nearest one.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"h": 0.5, "w": 0.4, "keys": [{"t": 0.5, "pos": Vector3(0, 5, 0), "rot": Vector3.ZERO}]},
		{"h": 1.5, "w": 0.4, "keys": [{"t": 0.5, "pos": Vector3(0, 15, 0), "rot": Vector3.ZERO}]},
	]}
	player.active_obstacle = Vector2(1.4, 0.4)
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 15.0, 0.001,
		"a 1.4 m obstacle did not borrow the 1.5 m row")
	player.active_obstacle = Vector2(0.7, 0.4)
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 5.0, 0.001,
		"a 0.7 m obstacle did not borrow the 0.5 m row")

func test_height_outweighs_width() -> void:
	# ⚠️ A metre of HEIGHT is a different move -- step-up against vault against
	# pull-up -- while a metre of WIDTH is the same move with the body further
	# from the far edge. Weighting them equally lets a wide low sill borrow a
	# tall thin one's curve, which is a different animation entirely.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"h": 1.0, "w": 2.0, "keys": [{"t": 0.5, "pos": Vector3(0, 1, 0), "rot": Vector3.ZERO}]},
		{"h": 1.6, "w": 0.1, "keys": [{"t": 0.5, "pos": Vector3(0, 2, 0), "rot": Vector3.ZERO}]},
	]}
	# Half a metre taller than the first row, but 1.6 m narrower than it.
	player.active_obstacle = Vector2(1.5, 0.4)
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 2.0, 0.001,
		"width outvoted height, so a low wide sill lent its curve to a tall one")

# A curve is zero at both ends of the move, and no key can say otherwise.
#
# THE OWNER made this a rule: "所有脚本驱动的动画首位帧默认都应该是0偏移，否则前后衔接上
# 肯定会出现闪现，这个得强制性."
#
# The reason it must be forced: outside a scripted move nothing reads the curve,
# so the offset is zero. A first key of +12 cm therefore does not START the move
# 12 cm off, it TELEPORTS the body 12 cm on the tick the move begins. The old
# sampler held the first key's value all the way back to t = 0, which made the
# pop the DEFAULT for any curve not hand-started at zero.

func test_a_curve_that_starts_off_zero_still_begins_at_zero() -> void:
	var player: Player = await _player_with_body()
	player.active_obstacle = Vector2(1.0, 0.5)
	player.body_clip_curves = {&"ClimbUp_2m": [{"h": 1.0, "w": 0.5, "keys": [
		{"t": 0.30, "pos": Vector3(0.0, 0.12, 0.0), "rot": Vector3.ZERO},
		{"t": 0.70, "pos": Vector3(0.0, 0.20, 0.0), "rot": Vector3.ZERO},
	]}]}
	var at_start: Array = player.clip_curve_at(&"ClimbUp_2m", 0.0)
	assert_eq(at_start[0], Vector3.ZERO, "the move began with the body already displaced")
	var at_end: Array = player.clip_curve_at(&"ClimbUp_2m", 1.0)
	assert_eq(at_end[0], Vector3.ZERO, "the move ended with the body still displaced")
	# And the keying in between is untouched -- this pins the ends, it does not
	# scale the curve.
	var middle: Array = player.clip_curve_at(&"ClimbUp_2m", 0.30)
	assert_almost_eq(float(middle[0].y), 0.12, 0.001, "the hand-keyed value was altered")

func test_a_key_sitting_on_an_end_is_ignored_rather_than_honoured() -> void:
	var player: Player = await _player_with_body()
	player.active_obstacle = Vector2(1.0, 0.5)
	# t = 0.005 is half a millisecond from the bookend: honoured, the lerp
	# between the two would be the same instant jump under another name.
	player.body_clip_curves = {&"ClimbUp_2m": [{"h": 1.0, "w": 0.5, "keys": [
		{"t": 0.005, "pos": Vector3(0.0, 0.40, 0.0), "rot": Vector3.ZERO},
		{"t": 0.500, "pos": Vector3(0.0, 0.10, 0.0), "rot": Vector3.ZERO},
	]}]}
	var early: Array = player.clip_curve_at(&"ClimbUp_2m", 0.01)
	assert_lt(absf(float(early[0].y)), 0.02,
		"a key inside the edge band still moved the body at the join")

# The same obstacle at two entry heights is two rows.
#
# THE OWNER: "相同的高度和宽度，不同的起跳时间是不是也有单独的存档，因为起跳时间可能会导致
# 一个完美 StepUp 变成补救型" -- and the mechanism, in their words: "进入脚本控制的瞬间，
# 玩家的起始高度不一样啊，怎么可能轨迹一样."
#
# Measured on one 1.0 x 0.4 obstacle, four jump timings that all vault: same
# clip, same landing, same 27 frames, and a start 0.69 m apart -- a fifth of the
# path's length. See ScriptedMove.entry_rise().

func test_the_nearer_entry_wins_when_the_obstacle_is_the_same() -> void:
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"h": 1.0, "w": 0.4, "e": 0.10,
			"keys": [{"t": 0.5, "pos": Vector3(0, 3, 0), "rot": Vector3.ZERO}]},
		{"h": 1.0, "w": 0.4, "e": 0.78,
			"keys": [{"t": 0.5, "pos": Vector3(0, 7, 0), "rot": Vector3.ZERO}]},
	]}
	player.active_obstacle = Vector2(1.0, 0.4)
	player.active_entry = 0.70
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 7.0, 0.001,
		"a late jump borrowed the well-timed row's curve")
	player.active_entry = 0.15
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 3.0, 0.001,
		"a well-timed jump borrowed the rescue row's curve")

func test_a_row_with_no_entry_still_matches_every_entry() -> void:
	# THE PAIR, and what keeps the axis additive: a table written before it
	# existed -- or one the owner only ever keys one row of -- behaves exactly as
	# it did, instead of being pinned to an entry of 0 it never meant.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [{"h": 1.0, "w": 0.4,
		"keys": [{"t": 0.5, "pos": Vector3(0, 5, 0), "rot": Vector3.ZERO}]}]}
	player.active_obstacle = Vector2(1.0, 0.4)
	for entry in [0.0, 0.4, 1.2]:
		player.active_entry = entry
		assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 5.0, 0.001,
			"an entry of %.1f found no row at all" % entry)

func test_an_exact_obstacle_is_never_outranked_by_a_better_entry() -> void:
	# THE OWNER: "对应宽高只要有一帧微调，就不要再使用其他接近参数的关键帧了，否则可能会互相
	# 影响导致某些高度在上下都懂[抖]."
	#
	# A real defect, one commit old: with the entry folded into the same weighted
	# sum, an exact obstacle match whose entry was 0.68 out scored 0.227 while a
	# row a quarter-metre taller with the entry spot on scored 0.063. Keying one
	# height changed another.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"h": 1.0, "w": 0.4, "e": 0.10,
			"keys": [{"t": 0.5, "pos": Vector3(0, 3, 0), "rot": Vector3.ZERO}]},
		{"h": 1.25, "w": 0.4, "e": 0.78,
			"keys": [{"t": 0.5, "pos": Vector3(0, 9, 0), "rot": Vector3.ZERO}]},
	]}
	player.active_obstacle = Vector2(1.0, 0.4)
	player.active_entry = 0.78
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 3.0, 0.001,
		"a taller obstacle's row won because its entry matched better")

func test_a_row_carrying_an_entry_beats_the_generic_one_beside_it() -> void:
	# Specific beats generic. A generic row sits at distance zero from every
	# entry, so ranking them together would let it win always and the axis would
	# never do anything.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"h": 1.0, "w": 0.4,
			"keys": [{"t": 0.5, "pos": Vector3(0, 5, 0), "rot": Vector3.ZERO}]},
		{"h": 1.0, "w": 0.4, "e": 0.78,
			"keys": [{"t": 0.5, "pos": Vector3(0, 9, 0), "rot": Vector3.ZERO}]},
	]}
	player.active_obstacle = Vector2(1.0, 0.4)
	player.active_entry = 0.70
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 9.0, 0.001,
		"the generic row shadowed the one keyed for this entry")

func test_an_emptied_row_does_not_shadow_its_neighbours() -> void:
	# A row is written the moment a combination is visited and emptied again by
	# dropping its last key. Left eligible it wins its own obstacle outright with
	# nothing in it, which reads as the curve having been deleted everywhere.
	var player: Player = await _player_with_body()
	player.body_clip_curves = {&"Idle": [
		{"h": 1.0, "w": 0.4, "keys": []},
		{"h": 1.25, "w": 0.4,
			"keys": [{"t": 0.5, "pos": Vector3(0, 6, 0), "rot": Vector3.ZERO}]},
	]}
	player.active_obstacle = Vector2(1.0, 0.4)
	assert_almost_eq(float(player.clip_curve_at(&"Idle", 0.5)[0].y), 6.0, 0.001,
		"an empty row was picked over a keyed neighbour")

func test_a_scripted_move_carries_the_eye_with_the_offset() -> void:
	# ✅ THE OWNER (StepUp): "动画做了偏移，第一人称镜头应该自动应用相同的偏移" --
	# during a SCRIPTED move the path owns the eye's journey and the clip
	# offset is part of the presentation, so the eye follows it. Outside one
	# the subtraction above stands: WallRun's +-0.7 lateral corrections must
	# never swing the view (see test_lowering_the_body_does_not_lower_the_camera).
	var player: Player = await _player_with_body()
	var head := Node3D.new()
	head.name = "FakeHead"
	player.body.add_child(head)
	head.position = Vector3(0.0, 1.5, 0.0)
	player.head_node = head
	player.head_rest_local = player.to_local(head.global_position)

	# A real ScriptedMove through the real manager, so scripted_progress()
	# is genuinely >= 0 rather than stubbed at the read site.
	var scripted := _BareScripted.new()
	scripted.player = player
	scripted.config = player.config
	scripted.cfg = MoveConfig.new()
	player.move_manager.add_child(scripted)
	player.move_manager.register(&"BareScripted", scripted)
	player.move_manager.start(&"BareScripted")
	assert_true(player.scripted_progress() >= 0.0, "test setup: no scripted path running")
	var rest: Vector3 = player._camera_head_offset()

	player.set_clip_offset_immediately(Vector3(0.0, 0.0, -0.20), Vector3.ZERO)
	var moved: float = player._camera_head_offset().distance_to(rest)
	assert_almost_eq(moved, 0.20, 0.001,
		"during a scripted move a 0.20 m clip offset moved the eye by %.3f m" % moved)

## Enters with a begun path and otherwise does nothing -- the smallest thing
## that makes scripted_progress() report a live path.
class _BareScripted extends ScriptedMove:
	func enter(_previous: StringName) -> void:
		player.set_grounded(false)
		begin(player.global_position, player.global_position + Vector3.FORWARD, 1.0)
