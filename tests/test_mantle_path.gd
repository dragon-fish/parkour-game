extends ParkourTest

# The shape and the length of a pull-up.
#
# ✅ THE OWNER, with a drawing: "脚本弧线不对，它的趋势应该是先垂直向上然后再往前送，
# 而不是一个完美的弧线，否则人会穿墙." And separately: "我们的 GrabPullUp 速度太快了，
# 它不应该比 VaultOver 还快."
#
# ⚠️ ONE EASED CURVE FOR ALL THREE AXES IS A FINE DESCRIPTION OF A VAULT and a
# wrong one for a pull-up. A vault really does go up and over in a single motion,
# and the thing it arcs over is BELOW it. A pull-up is the opposite shape: the
# obstacle is the face you are hanging on, so every centimetre of forward travel
# spent before the crown clears the lip is spent inside it.

const TestWorld = preload("res://tests/world_fixture.gd")

const LEDGE_TOP := 2.0
const LEDGE_FACE_Z := -1.5
const EDGE := Vector3(0.0, LEDGE_TOP, -1.6)
const FACE_NORMAL := Vector3(0.0, 0.0, 1.0)
const TOP_NORMAL := Vector3(0.0, 1.0, 0.0)

var _extra: Array[Node] = []
var _world: Dictionary = {}

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _mantling_player() -> Array:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, LEDGE_TOP, 1.0)
	shape.shape = box
	body.add_child(shape)
	player.get_parent().add_child(body)
	body.global_position = Vector3(0.0, LEDGE_TOP * 0.5, LEDGE_FACE_Z - 0.5)
	_extra.append(body)
	player.rotation.y = 0.0
	var query := {"valid": true, "edge": EDGE, "top": EDGE,
			"normal": TOP_NORMAL, "face_normal": FACE_NORMAL}
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.pending_ledge = query
	player.move_manager.start(Move.GRAB)
	await step(1)
	var grab := player.move_manager.move_for(Move.GRAB) as GrabMove
	var forward := MoveInput.new()
	forward.move = Vector2(0.0, 1.0)
	var start: Vector3 = player.global_position
	grab.physics_update(0.001, forward)
	return [player, grab, start]

# --- the shape ------------------------------------------------------------------

func test_a_lead_keeps_the_body_over_the_lip_before_it_travels() -> void:
	# ⚠️ THE INVARIANT, and it took two goes to state. The first version pinned
	# the travel to under 20% at 40% of the way through, which was true of the
	# two-phase hook it was written against and false of the composite that
	# replaced it -- there the crossing starts at 0.28 and is deliberately linear
	# after that. The number moved; what matters did not.
	#
	# What matters is not WHEN the body moves forward, it is WHERE IT IS when it
	# does: every centimetre of forward travel spent below the lip is spent
	# inside the wall. So walk the path and check the height at the moment the
	# travel first becomes real.
	# ⚠️ THIS PINS THE MACHINERY, NOT THE DEFAULT, and the difference is the
	# owner's own methodology arriving:
	#
	# ✅ "胶囊体的运动不一定要符合物理规律，它越简单越好，是镜头和动画去配合它."
	#
	# So the shipped mantle is back to one curve, and the body passing through
	# the face is not a defect to be designed out -- the animation and the camera
	# cover it. The composite path stays available and stays tested, because the
	# day something genuinely needs a hooked path it should not have to be
	# rediscovered. See docs/capsule-leads-presentation.md.
	var bits: Array = await _mantling_player()
	var player: Player = bits[0]
	var grab: GrabMove = bits[1]
	var start: Vector3 = bits[2]
	assert_true(grab.is_mantling(), "the fixture never started a pull-up")
	grab.begin(start, grab._to, player.config.grab.mantle_duration,
		player.config.grab.mantle_arc_height, 1.0)
	var target: Vector3 = grab._to
	var span: float = absf(target.z - start.z)
	var slice: float = player.config.grab.mantle_duration / 40.0
	var caught := false
	for i in 40:
		grab.physics_update(slice, forward_input())
		var travel: float = absf(player.global_position.z - start.z) / maxf(span, 0.0001)
		if travel < 0.2:
			continue
		caught = true
		assert_gt(player.global_position.y, LEDGE_TOP - 0.05,
			"the body was at y %.2f -- below the lip at %.2f -- with %.0f%% of the travel already spent"
			% [player.global_position.y, LEDGE_TOP, travel * 100.0])
		break
	assert_true(caught, "the pull-up never travelled forward at all")

func test_it_still_arrives_where_it_was_aimed() -> void:
	# The pair: a hook that never completes its travel leaves the player hanging
	# in the air over the lip.
	var bits: Array = await _mantling_player()
	var player: Player = bits[0]
	var grab: GrabMove = bits[1]
	var target: Vector3 = grab._to
	grab.physics_update(player.config.grab.mantle_duration * 2.0, forward_input())
	assert_almost_eq(player.global_position.distance_to(target), 0.0, 0.02,
		"the pull-up finished %.3f m from where it aimed"
		% player.global_position.distance_to(target))

func test_a_lead_of_zero_is_the_old_single_curve() -> void:
	# ⚠️ THE PROMISE THE PARAMETER MAKES, and the one everything else in the game
	# relies on: SpeedVault drives the same begin(), and a vault genuinely does
	# travel up and over as ONE motion over something BELOW it. Zero has to mean
	# "exactly as before", not "nearly".
	#
	# 📌 The first version of this test asserted a table value equalled itself.
	# It passed, and proved nothing -- which is the failure mode this whole file
	# is about, in miniature.
	var bits: Array = await _mantling_player()
	var player: Player = bits[0]
	var grab: GrabMove = bits[1]
	var start: Vector3 = bits[2]
	# Re-aim the same move with no lead at all.
	player.config.grab.mantle_vertical_lead = 0.0
	grab.begin(start, grab._to, player.config.grab.mantle_duration, 0.0, 0.0)
	grab.physics_update(player.config.grab.mantle_duration * 0.4, forward_input())
	var target: Vector3 = grab._to
	var rise: float = (player.global_position.y - start.y) / maxf(target.y - start.y, 0.0001)
	var travel: float = absf(player.global_position.z - start.z) 			/ maxf(absf(target.z - start.z), 0.0001)
	# One curve for both axes means they are at the same fraction of the way.
	assert_almost_eq(rise, travel, 0.01,
		"with no lead the rise was %.2f and the travel %.2f, which is not one curve"
		% [rise, travel])

# --- the length -----------------------------------------------------------------

func test_a_pull_up_is_slower_than_a_vault_over() -> void:
	# ✅ THE OWNER: "它不应该比 VaultOver 还快."
	#
	# 📌 AND THE ORIGINAL HAS NO NUMBER TO COPY -- TdMove_GrabPullUp carries no
	# duration field at all, which says the length comes from the animation. So
	# the reference is the vault table beside it, read from the table rather than
	# repeated here, so retuning a vault cannot silently make this true again.
	var config := MovementConfig.new()
	var quickest := INF
	for variant in config.speed_vault.variants:
		if not bool(variant.get("vault_onto", true)):
			quickest = minf(quickest, float(variant.get("duration", INF)))
	assert_lt(quickest, INF, "no vault-over row in the table to compare against")
	assert_gt(config.grab.mantle_duration, quickest,
		"a pull-up takes %.2f s against the quickest vault-over's %.2f"
		% [config.grab.mantle_duration, quickest])

func forward_input() -> MoveInput:
	var input := MoveInput.new()
	input.move = Vector2(0.0, 1.0)
	return input
