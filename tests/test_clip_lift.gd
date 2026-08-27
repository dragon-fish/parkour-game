extends ParkourTest

# A scripted move owns the body's height, so the CLIP must not add its own.
#
# DO NOT try to compensate by moving the ROOT NODE. Non-root-motion only
# guarantees the ROOT NODE does not translate; it says nothing about the
# HIPS, which are a bone like any other, and an in-place vault clip lifts them
# exactly as much as the real one moved. Measured across the library:
#
#     Idle          0.009 m     flat
#     Sprint        0.151 m     an ordinary run's bob
#     StepUp        0.477 m
#     SafetyVault   0.825 m     hips from 0.904 up to 1.729
#     ClimbUp_2m    1.201 m
#
# During a vault the arc already carries the body over the obstacle, so the
# clip's lift is the same metre counted twice -- and moving the root could
# never fix it, because the root was never where the body was.

const TestWorld = preload("res://tests/world_fixture.gd")

const HIPS_REST := 0.95

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A body with a real Skeleton3D carrying one Hips bone, so the lift can be
## posed by hand. Built at runtime, so this depends on no untracked model.
func _player_with_skeleton(mount_scale: float = 1.0) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var root := Node3D.new()
	root.name = "fake_body"
	var skeleton := Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	skeleton.add_bone("Hips")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0.0, HIPS_REST, 0.0)))
	skeleton.set_bone_pose_position(0, Vector3(0.0, HIPS_REST, 0.0))
	root.add_child(skeleton)
	skeleton.owner = root
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	library.add_animation(&"Idle", animation)
	anim_player.add_animation_library("", library)
	root.add_child(anim_player)
	anim_player.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	player.body_mount_scale = mount_scale
	player._attach_body(packed)
	return player

func _pose_hips(player: Player, y: float) -> void:
	var skeleton := player.body.get_node("GeneralSkeleton") as Skeleton3D
	skeleton.set_bone_pose_position(0, Vector3(0.0, y, 0.0))

# --- the measurement ---------------------------------------------------------------

func test_the_lift_is_the_hips_above_their_rest() -> void:
	var player: Player = await _player_with_skeleton()
	assert_almost_eq(player.clip_lift(), 0.0, 0.0001, "a body at rest reported a lift")
	_pose_hips(player, HIPS_REST + 0.825)
	assert_almost_eq(player.clip_lift(), 0.825, 0.0001,
		"a hips lift of 0.825 read as %.3f" % player.clip_lift())

func test_the_lift_is_measured_in_world_metres() -> void:
	# Bone space is MODEL space, so a scaled model lifts its hips further in
	# the world than the track says. Getting this wrong under-corrects on every
	# model that is not exactly 1.0.
	var player: Player = await _player_with_skeleton(1.22)
	_pose_hips(player, HIPS_REST + 0.5)
	assert_almost_eq(player.clip_lift(), 0.5 * 1.22, 0.0001,
		"a scaled model reported %.3f" % player.clip_lift())

# --- what it does to the body --------------------------------------------------------

func test_a_scripted_move_takes_the_lift_back_off_the_root() -> void:
	var player: Player = await _player_with_skeleton()
	var resting: float = player.body.position.y
	_pose_hips(player, HIPS_REST + 0.825)
	player.set_clip_lift_cancelled(true)
	# Long enough for the ease to arrive. EASED, not switched: a binary
	# cancellation snaps the body in one frame when the clip still has its hips
	# raised at hand-off.
	await step(60)
	assert_almost_eq(player.body.position.y, resting - 0.825, 0.01,
		"the root moved %.3f m for a lift of 0.825"
		% (resting - player.body.position.y))

func test_ordinary_locomotion_keeps_its_bob() -> void:
	# A run's 0.151 m IS the bob. Cancelling it everywhere would flatten the
	# walk into a glide, which is why this is a declaration rather than
	# something read off the skeleton.
	var player: Player = await _player_with_skeleton()
	var resting: float = player.body.position.y
	_pose_hips(player, HIPS_REST + 0.151)
	await step(3)
	assert_almost_eq(player.body.position.y, resting, 0.001,
		"a run's bob was cancelled: the root moved %.3f m"
		% (resting - player.body.position.y))

func test_a_body_with_no_hips_reports_nothing() -> void:
	# Every other non-humanoid guard in this file's neighbours does the same.
	var player: Player = await _player_with_skeleton()
	player._hips_bone = -1
	assert_almost_eq(player.clip_lift(), 0.0, 0.0001, "a body with no hips reported a lift")

func test_the_cancellation_eases_out_rather_than_snapping() -> void:
	# A clip cut short still has its hips up when the move hands off, so a
	# binary switch of the cancellation snaps 0.825 m out of the body in one
	# frame -- the ease must ramp this out over several ticks instead.
	var player: Player = await _player_with_skeleton()
	var resting: float = player.body.position.y
	_pose_hips(player, HIPS_REST + 0.825)
	player.set_clip_lift_cancelled(true)
	await step(60)
	var folded: float = player.body.position.y
	player.set_clip_lift_cancelled(false)
	await step(1)
	var after_one_tick: float = player.body.position.y
	assert_lt(after_one_tick - folded, 0.4,
		"the body sprang %.2f m in a single tick" % (after_one_tick - folded))
	await step(60)
	assert_almost_eq(player.body.position.y, resting, 0.01,
		"it never finished coming back")
