extends ParkourTest

# Travelling along a ledge you are already hanging from.
#
# ✅ The owner asked for the Climb set to be used, and UAL1 is the one pack that
# carries a whole hang vocabulary: Climb_Idle, Climb_Left, Climb_Right,
# ClimbLedge. Both travel clips are 0.87 s with ZERO net displacement, so the
# clip supplies the pose and the code supplies the metres -- the arrangement
# this project already uses everywhere else.
#
# The thing under test is not "does it move". It is that the BODY and the
# ANCHOR move together or neither moves. _edge is what the pull-up aims at, so
# an anchor that has crept past the real ledge mantles the player onto thin
# air, and a body that has crept past its anchor hangs from a point the ledge
# no longer occupies.

const TestWorld = preload("res://tests/world_fixture.gd")

## The ledge block: 6 m of it, top at y = 2, front face at z = -1.5.
const LEDGE_TOP := 2.0
const LEDGE_FACE_Z := -1.5
const LEDGE_HALF_X := 3.0
## Just inside the lip, which is where Probes.ledge_query() anchors.
const EDGE := Vector3(0.0, LEDGE_TOP, -1.6)
## The WALL FACE's normal, pointing away from the wall and back at the player.
const FACE_NORMAL := Vector3(0.0, 0.0, 1.0)
## ⚠️ AND THE LEDGE TOP'S, WHICH IS A DIFFERENT THING AND IS WHY THIS EXISTS.
## ledge_query() returns both, perpendicular to each other: "normal" comes off
## SurfaceDown -- the ray fired DOWNWARD onto the top -- so it points straight
## up, while "face_normal" comes off the forward ray that found the wall.
##
## The first version of this file fed FACE_NORMAL under the key "normal" and
## did not set "face_normal" at all. Every test passed. The feature had never
## once run: the move read "normal", got straight up, flattened it to a zero
## vector and refused on every tick, and the owner found it in play. A fixture
## that hands over a shape the real producer never produces is not a fixture.
const TOP_NORMAL := Vector3(0.0, 1.0, 0.0)

## ⚠️ TRACKED SO after_each() CAN FREE THEM. TestWorld.teardown() frees only
## the player and the floor, so anything a test adds beside them OUTLIVES the
## test that added it -- and the world is rebuilt at the same coordinates every
## time, so a leaked slab is still exactly where it was put. That is how "a
## spent slide in the open" came to run under the previous test's roof and
## report no headroom.
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

func _hanging_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	_add_block(player, Vector3(0.0, LEDGE_TOP * 0.5, LEDGE_FACE_Z - 0.5),
			Vector3(LEDGE_HALF_X * 2.0, LEDGE_TOP, 1.0))
	player.rotation.y = 0.0
	# Shaped exactly as Probes.ledge_query() shapes it -- see TOP_NORMAL.
	var query := {"valid": true, "edge": EDGE, "top": EDGE,
			"normal": TOP_NORMAL, "face_normal": FACE_NORMAL}
	# ⚠️ PLACED BY IntoGrabMove.hanging_pose(), NOT BY HAND, and this file
	# learned why the hard way. The first version parked the body at a made-up
	# y = 1.2 on a 2 m wall, where a standing capsule comfortably fits. The real
	# pose does not: it puts 0.09 m of capsule above the lip and 0.05 m of it
	# through the wall face, so the body is always INSIDE the ledge it hangs
	# from. The shimmy gated on fits_standing_at(), which therefore said no on
	# every tick of every shimmy -- and these tests passed anyway, because the
	# hand-placed pose was the one pose in the game where that gate opens.
	# A fixture that stands the body somewhere the game never stands it tests
	# a game that does not exist.
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.pending_ledge = query
	player.move_manager.start(Move.GRAB)
	await step(1)
	return player

func _add_block(player: Player, centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	player.get_parent().add_child(body)
	body.global_position = centre
	_extra.append(body)
	return body

func _grab(player: Player) -> GrabMove:
	return player.move_manager.move_for(Move.GRAB) as GrabMove

func _hold(sideways: float, forward: float = 0.0) -> MoveInput:
	var input := MoveInput.new()
	input.move = Vector2(sideways, forward)
	return input

# --- the probe on its own ---------------------------------------------------

func test_the_ledge_is_found_where_it_continues() -> void:
	var player: Player = await _hanging_player()
	var beside: Dictionary = player.probes.ledge_beside(
			EDGE, Vector3(1.0, 0.0, 0.0), FACE_NORMAL, 0.1, 0.3, 0.15)
	assert_true(beside.get("valid", false), "1 m along a 6 m ledge found nothing")
	assert_almost_eq(float(beside["edge"].y), LEDGE_TOP, 0.02,
		"the ledge top came back at %.2f instead of %.2f"
		% [beside["edge"].y, LEDGE_TOP])

func test_the_ledge_is_not_found_past_its_end() -> void:
	# THE ONE THAT MATTERS. A probe that answers "yes" here would walk the
	# hands off the end of the ledge and leave the body hanging on nothing.
	var player: Player = await _hanging_player()
	var beside: Dictionary = player.probes.ledge_beside(
			EDGE, Vector3(LEDGE_HALF_X + 1.0, 0.0, 0.0), FACE_NORMAL, 0.1, 0.3, 0.15)
	assert_false(beside.get("valid", false),
		"a point 1.0 m past the end of a %.1f m ledge reported a ledge"
		% LEDGE_HALF_X)

func test_a_ledge_at_a_different_height_is_a_different_ledge() -> void:
	# The hanging body is placed for ONE height. A step up or down that the
	# body does not follow leaves it hanging from somewhere it is not.
	var player: Player = await _hanging_player()
	_add_block(player, Vector3(4.0, LEDGE_TOP, LEDGE_FACE_Z - 0.5),
			Vector3(2.0, LEDGE_TOP, 1.0))
	# That block's top is a whole LEDGE_TOP higher, well past the tolerance.
	var beside: Dictionary = player.probes.ledge_beside(
			EDGE, Vector3(4.0, 0.0, 0.0), FACE_NORMAL, 0.1, 0.3, 0.15)
	assert_false(beside.get("valid", false),
		"a ledge %.1f m higher was accepted as the same one" % LEDGE_TOP)

# --- which way is right -----------------------------------------------------

func test_holding_right_travels_to_the_players_right() -> void:
	# ⚠️ THE SIGN, and it is derived from the WALL rather than from the body on
	# purpose -- a hanging player may turn to look along the ledge, and taking
	# "sideways" off their own basis would swap A and D when they did.
	# Facing the wall means facing -Z here, so their right hand is +X.
	var player: Player = await _hanging_player()
	var before: float = player.global_position.x
	_grab(player).physics_update(0.5, _hold(1.0))
	assert_gt(player.global_position.x, before + 0.05,
		"holding right moved the body to x %.2f from %.2f"
		% [player.global_position.x, before])

func test_holding_left_travels_the_other_way() -> void:
	var player: Player = await _hanging_player()
	var before: float = player.global_position.x
	_grab(player).physics_update(0.5, _hold(-1.0))
	assert_lt(player.global_position.x, before - 0.05,
		"holding left moved the body to x %.2f from %.2f"
		% [player.global_position.x, before])

# --- the body and the anchor move together ----------------------------------

func test_the_anchor_travels_with_the_body() -> void:
	# An anchor left behind is what the pull-up would aim at, so a shimmy that
	# moves only the body mantles the player back to where they started.
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	var body_before: float = player.global_position.x
	grab.physics_update(0.5, _hold(1.0))
	var moved: float = player.global_position.x - body_before
	assert_gt(moved, 0.05, "the body did not travel at all")
	assert_almost_eq(grab._edge.x - EDGE.x, moved, 0.02,
		"the body moved %.3f m but the anchor moved %.3f m"
		% [moved, grab._edge.x - EDGE.x])

func test_running_out_of_ledge_moves_neither() -> void:
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	# Park the anchor and the body at the very end of the block.
	var end_edge := Vector3(LEDGE_HALF_X - 0.02, LEDGE_TOP, EDGE.z)
	grab._edge = end_edge
	# Through hanging_pose() again, for the reason spelled out in the fixture:
	# a hand-picked offset is the one place the body fits, and that is not where
	# the game puts it.
	player.global_position = IntoGrabMove.hanging_pose(player, player.config,
			{"edge": end_edge, "face_normal": FACE_NORMAL})
	var body_before: Vector3 = player.global_position
	var edge_before: Vector3 = grab._edge
	grab.physics_update(0.5, _hold(1.0))
	assert_almost_eq(player.global_position.distance_to(body_before), 0.0, 0.001,
		"the body travelled off the end of the ledge")
	assert_almost_eq(grab._edge.distance_to(edge_before), 0.0, 0.001,
		"the anchor travelled off the end of the ledge")

## THE BODY HAS WIDTH, AND THE LEDGE'S END IS WHERE THE BODY'S END MEETS IT.
## The owner, with a screenshot of a body hanging half over open air: the
## reach and the corner tests have to be made of the capsule's leading side,
## not of its centre line, "否则角色会出现半个身体悬空或穿进墙里的情况".
func test_the_leading_side_never_passes_the_end_of_the_ledge() -> void:
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	var half: float = player.config.grab.shimmy_body_half_width
	# Travel right until the ledge runs out. The block's east end is a real
	# perpendicular face, so this ends in a corner rather than in a refusal --
	# either way, where the body got to before it stopped travelling is the
	# thing under test.
	var furthest: float = player.global_position.x
	for i in 600:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if grab.is_cornering():
			break
		furthest = maxf(furthest, player.global_position.x)
	assert_lt(furthest + half, LEDGE_HALF_X + 0.01,
		"the body's leading side reached x %.2f on a ledge that ends at %.2f"
		% [furthest + half, LEDGE_HALF_X])

# --- what does not start a shimmy -------------------------------------------

func test_a_brushed_key_does_not_start_a_shimmy() -> void:
	# While hanging, this axis is a hair away from doing nothing at all, and a
	# body that creeps along the ledge because a key was brushed reads as a bug.
	var player: Player = await _hanging_player()
	var before: Vector3 = player.global_position
	_grab(player).physics_update(0.5, _hold(0.2))
	assert_almost_eq(player.global_position.distance_to(before), 0.0, 0.001,
		"a 0.2 nudge moved the body %.3f m"
		% player.global_position.distance_to(before))

func test_holding_forward_climbs_rather_than_shimmies() -> void:
	# Holding forward-and-right should pull up, not travel: the pull-up is the
	# committed action of the two, and this is what the `else` in the move
	# encodes.
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	var before: float = player.global_position.x
	grab.physics_update(0.5, _hold(1.0, 1.0))
	assert_almost_eq(player.global_position.x, before, 0.001,
		"a forward-and-right hold shimmied %.3f m sideways"
		% (player.global_position.x - before))
	assert_almost_eq(grab.shimmy_direction(), 0.0, 0.001,
		"the animator would have been told to play a travel clip while mantling")

# --- what the animator is told ----------------------------------------------

func test_the_travel_direction_is_reported_for_the_animator() -> void:
	# Nothing outside the move can tell a hang apart from a shimmy, which is
	# why this is exposed at all -- same reason is_mantling() is.
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	assert_almost_eq(grab.shimmy_direction(), 0.0, 0.001,
		"a fresh hang already reported travel")
	grab.physics_update(0.5, _hold(1.0))
	assert_almost_eq(grab.shimmy_direction(), 1.0, 0.001, "travelling right was not reported")
	grab.physics_update(0.5, _hold(-1.0))
	assert_almost_eq(grab.shimmy_direction(), -1.0, 0.001, "travelling left was not reported")
	grab.physics_update(0.5, _hold(0.0))
	assert_almost_eq(grab.shimmy_direction(), 0.0, 0.001,
		"letting go left the travel clip playing")

# --- the two normals ----------------------------------------------------------

func test_the_wall_face_decides_the_direction_not_the_ledge_top() -> void:
	# ⚠️ THE REGRESSION. ledge_query() returns "normal" (the ledge TOP's, which
	# points straight up) and "face_normal" (the WALL's). Reading the first one
	# leaves nothing behind once y is dropped, and the move then refuses to
	# travel on every tick -- silently, because refusing is an ordinary thing
	# for it to do. That shipped, and only play caught it.
	#
	# Fed here with ONLY the top normal, the way a caller that forgot the face
	# would: the move must fall back to the body's facing rather than sit there.
	var player: Player = await _hanging_player()
	player.move_manager.start(Move.WALKING)
	player.global_position = Vector3(0.0, 1.2, -1.05)
	player.rotation.y = 0.0
	player.pending_ledge = {"valid": true, "edge": EDGE, "top": EDGE,
			"normal": TOP_NORMAL}
	player.move_manager.start(Move.GRAB)
	await step(1)
	var before: float = player.global_position.x
	_grab(player).physics_update(0.5, _hold(1.0))
	assert_gt(player.global_position.x, before + 0.05,
		"a query carrying only the ledge-top normal froze the shimmy")

# --- travelling needs both hands ------------------------------------------------

func test_a_one_handed_hang_cannot_travel() -> void:
	# 🎯 THE OWNER'S MODEL, which explains two restrictions with one cause: "ME 里
	# 扭头大于 45° 会变成单手攀附，很多事情就解释的通，此时无法 AD，也无法 GrabUp，
	# 因为这两种动作都要求 2 hands free."
	#
	# The CDO agrees from its own side: TdMove_Grab carries
	# MovementGroup = MG_TwoHandsBusy.
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	# Turned well past the threshold. rotation.y = 0 faces this wall squarely.
	player.rotation.y = deg_to_rad(90.0)
	var before: Vector3 = player.global_position
	grab.physics_update(0.5, _hold(1.0))
	assert_almost_eq(player.global_position.distance_to(before), 0.0, 0.001,
		"a body hanging by one arm travelled %.3f m along the ledge"
		% player.global_position.distance_to(before))
	assert_almost_eq(grab.shimmy_direction(), 0.0, 0.001,
		"the animator was told to play a travel clip on a one-handed hang")

func test_squaring_back_up_lets_travel_resume() -> void:
	# The pair: the gate is a STATE, not a lockout, so looking back at the wall
	# gives the hand back immediately.
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	player.rotation.y = deg_to_rad(90.0)
	grab.physics_update(0.5, _hold(1.0))
	player.rotation.y = 0.0
	var before: float = player.global_position.x
	grab.physics_update(0.5, _hold(1.0))
	assert_gt(player.global_position.x, before + 0.05,
		"travel did not resume once the view came back to the wall")

# --- a buried ledge is not a ledge ------------------------------------------------

## The arena's own shaft, which is where the owner found this: a 2.7 m step with
## a 6.3 m block standing ON it, overlapping for 2.2 m of the step's length. The
## north faces are coplanar at z = 43, so a shimmy travelling along that face
## crosses from the exposed rim into the buried strip without anything changing
## in front of it.
const SHAFT_FACE_Z := 43.0
const SHAFT_TOP := 2.70
const SHAFT_TALL_EAST := 34.0

func _shaft(player: Player) -> void:
	_add_block(player, Vector3(33.30, SHAFT_TOP * 0.5, 40.0),
			Vector3(3.0, SHAFT_TOP, 6.0))
	_add_block(player, Vector3(32.50, 3.15, 40.0), Vector3(3.0, 6.30, 6.0))

func test_a_top_with_a_block_standing_on_it_is_refused() -> void:
	# ✅ THE OWNER, hanging inside a wall: "我们的攀爬好像没考虑这种可攀附点被遮挡的
	# 情况."
	#
	# ⚠️ AND ledge_query() WAS ALREADY RIGHT, which is why the grab looked fine
	# and the travel did not. SurfaceDown has always set hit_from_inside, so the
	# entry probe refused the buried strip. These probes did not: a Godot ray
	# that begins inside a shape and is not told so IGNORES that shape and
	# reports the next hit along -- straight through the tall block, onto the
	# step buried underneath it, which it then called a ledge.
	var player: Player = await _hanging_player()
	_shaft(player)
	await step(2)
	var buried := Vector3(32.90, SHAFT_TOP, SHAFT_FACE_Z - 0.1)
	var found: Dictionary = player.probes.ledge_beside(buried, Vector3.ZERO,
			Vector3(0.0, 0.0, 1.0), 0.1, 0.3, 0.15)
	assert_false(found.get("valid", false),
		"a step buried under a six-metre block was reported as a ledge")

func test_the_exposed_rim_beside_it_still_works() -> void:
	# The pair, and it is doing real work: the strip either side of x = 34 is the
	# SAME step at the SAME height on the SAME coplanar face. Only the block
	# standing on half of it differs, so a fix that refused both would be
	# indistinguishable here from one that refuses everything.
	var player: Player = await _hanging_player()
	_shaft(player)
	await step(2)
	var exposed := Vector3(SHAFT_TALL_EAST + 0.4, SHAFT_TOP, SHAFT_FACE_Z - 0.1)
	var found: Dictionary = player.probes.ledge_beside(exposed, Vector3.ZERO,
			Vector3(0.0, 0.0, 1.0), 0.1, 0.3, 0.15)
	assert_true(found.get("valid", false),
		"the exposed rim beside the tall block stopped being a ledge")

# --- the body is wider than its capsule -----------------------------------------

func test_a_wall_stops_the_hand_not_the_chest() -> void:
	# ✅ THE OWNER: "能不能给横爬障碍的探测加一个身体宽度，现在是角色的中心撞到障碍才
	# 会被阻挡，但其实人的手已经进入墙里了."
	#
	# ⚠️ THE CAPSULE IS THE WRONG SHAPE FOR THIS. Its 0.4 m radius describes a
	# cylinder around the torso, and a person hanging by their hands is not that:
	# the arms are up and out, and the leading hand is both wider than the
	# shoulder and 0.81 m higher than the body's centre.
	#
	# The block below is placed so that a capsule-radius probe would still say
	# "clear" while a body-width one says "blocked" -- the gap between the two is
	# the whole finding.
	var player: Player = await _hanging_player()
	var grab := _grab(player)
	var half: float = player.config.grab.shimmy_body_half_width
	var radius: float = player.current_capsule_radius()
	assert_gt(half, radius + 0.05,
		"the configured half-width (%.2f) is not meaningfully wider than the capsule (%.2f)"
		% [half, radius])
	# A pillar squarely in the hand's way, inside the body width and outside the
	# capsule radius.
	var at: float = player.global_position.x + (half + radius) * 0.5
	_add_block(player, Vector3(at + 0.3, LEDGE_TOP * 0.5, player.global_position.z),
			Vector3(0.6, LEDGE_TOP * 2.0, 0.6))
	await step(2)
	var before: float = player.global_position.x
	grab.physics_update(1.0 / 60.0, _hold(1.0))
	assert_almost_eq(player.global_position.x, before, 0.001,
		"the hand travelled %.3f m into a pillar %.2f m away"
		% [player.global_position.x - before, at - before])

func test_an_open_ledge_is_still_travelled() -> void:
	# The pair. A half-width wide enough to stop a hand is also wide enough to
	# stop everything if the probe is pointed wrongly, and this file's whole
	# subject is a shimmy that silently refuses.
	var player: Player = await _hanging_player()
	var before: float = player.global_position.x
	_grab(player).physics_update(0.5, _hold(1.0))
	assert_gt(player.global_position.x, before + 0.05,
		"widening the probe stopped travel on an open ledge")
