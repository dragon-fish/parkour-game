extends ParkourTest

# DO NOT let a test that pins a removed field sit and go red indefinitely --
# a suite everyone is used to seeing red stops being able to report the next
# real regression. GrabConfig.mantle_vertical_lead and
# MovementConfig.scripted_path_arcs (a two-curve pull-up path with an
# optional camera arc) no longer exist; the single composite bezier that
# replaced them is what the tests below cover.

# The shape and the length of a pull-up.
#
# A pull-up's travel path must stay near-vertical past the lip before it goes
# forward -- a smooth single arc lets the capsule cut straight through the
# wall it is climbing. And GrabPullUp must not run faster than a vault-over
# (see below for why that number has nowhere else to come from).
#
# ONE EASED CURVE FOR ALL THREE AXES IS A FINE DESCRIPTION OF A VAULT and a
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

## `roof_clearance` puts a ceiling that far above the ledge, which is what an
## opening in a wall is: a lip with something solid over it. Zero means open
## sky, the shape every test here had before.
func _mantling_player(roof_clearance: float = 0.0) -> Array:
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
	if roof_clearance > 0.0:
		var roof := StaticBody3D.new()
		var roof_shape := CollisionShape3D.new()
		var roof_box := BoxShape3D.new()
		roof_box.size = Vector3(6.0, 1.0, 3.0)
		roof_shape.shape = roof_box
		roof.add_child(roof_shape)
		player.get_parent().add_child(roof)
		roof.global_position = Vector3(0.0, LEDGE_TOP + roof_clearance + 0.5,
			LEDGE_FACE_Z - 1.0)
		_extra.append(roof)
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
	# THE INVARIANT: what matters is not WHEN the body moves forward, it is
	# WHERE IT IS when it does. Every centimetre of forward travel spent below
	# the lip is spent inside the wall -- so walk the path and check the height
	# at the moment the travel first becomes real, rather than pinning a
	# travel-percentage number that is only true of one particular curve shape.
	#
	# THIS PINS THE MACHINERY, NOT THE DEFAULT. The capsule's own path does not
	# need to look physically plausible -- the simpler it is, the better, since
	# the camera and the animation are what sell the motion, not the capsule.
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
		0.0, 1.0)
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

func test_a_pull_up_is_slower_than_a_vault_over() -> void:
	# GrabPullUp must not be faster than a vault-over.
	#
	# [ME:CONFIRMED] The original has no number to copy here -- TdMove_GrabPullUp
	# carries no duration field at all, which says the length comes from the
	# animation instead. So the reference is the vault table beside it, read
	# from the table rather than repeated here, so retuning a vault cannot
	# silently make this true again.
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

# --- the simplest possible path ---------------------------------------------

func test_the_ease_is_still_there_for_anything_that_asks() -> void:
	# The pair. "Linear by default" is a decision about the DEFAULT, and a move
	# that wants the old push-off shape should not have to reinstate it in code.
	var bits: Array = await _mantling_player()
	var player: Player = bits[0]
	var grab: GrabMove = bits[1]
	var start: Vector3 = bits[2]
	var target: Vector3 = grab._to
	grab.begin(start, target, player.config.grab.mantle_duration, 0.0, 0.0, 2.0)
	var at: Vector3 = grab.sample(0.5)
	var straight: Vector3 = start.lerp(target, 0.5)
	assert_gt(at.distance_to(straight), 0.05,
		"asking for an ease of 2.0 still produced a straight line")


# --- climbing into an opening ----------------------------------------------------

func test_an_opening_too_low_to_stand_in_is_still_climbed_into() -> void:
	# A vent or a duct: 1.28 m of clear height, which no standing body fits in
	# and every folded one does -- and folding is what a pull-up does, thirty
	# lines into GrabMove.physics_update().
	#
	# The gate was handed `top`, the capsule's CENTRE, by a function that
	# builds its capsule up from the FEET. That lifted the test body 0.9 m and
	# measured the wall above the opening rather than the opening.
	var bits: Array = await _mantling_player(1.278)
	var grab: GrabMove = bits[1]
	assert_true(grab.is_mantling(), \
		"a 1.28 m opening refused a climb that folds down to 0.9 m")

func test_a_gap_no_body_fits_through_is_still_refused() -> void:
	# The control. Measuring at the crouch height must not become measuring at
	# nothing: pulling up into a slab is the clipping this gate exists to stop.
	var bits: Array = await _mantling_player(0.5)
	var grab: GrabMove = bits[1]
	assert_false(grab.is_mantling(), \
		"a 0.5 m gap admitted a pull-up no body could survive")


func test_a_climb_into_an_opening_ends_crouched_not_walking() -> void:
	# The capsule stays folded under a roof -- request_standing_capsule() sees
	# to that -- but the MOVE decides the animation, and Walking over a 0.9 m
	# capsule is a standing body with its head through the ceiling.
	var bits: Array = await _mantling_player(1.278)
	var player: Player = bits[0]
	var grab: GrabMove = bits[1]
	assert_true(grab.is_mantling(), "the fixture never started a pull-up")
	var landed: StringName = Move.KEEP
	for i in 200:
		landed = grab.physics_update(1.0 / 60.0, MoveInput.new())
		if landed != Move.KEEP:
			break
		await step(1)
	assert_eq(landed, Move.CROUCH, \
		"a pull-up under a roof handed the body to a standing move")
	assert_false(player.has_headroom(), "the fixture left room to stand after all")

func test_a_climb_into_open_sky_still_ends_walking() -> void:
	# The control: nothing above the ledge must still walk out of the climb.
	var bits: Array = await _mantling_player()
	var grab: GrabMove = bits[1]
	var landed: StringName = Move.KEEP
	for i in 200:
		landed = grab.physics_update(1.0 / 60.0, MoveInput.new())
		if landed != Move.KEEP:
			break
		await step(1)
	assert_eq(landed, Move.WALKING, "an open ledge stopped handing over to Walking")

func test_a_climb_into_an_opening_knows_it_cannot_stand() -> void:
	# What the animator reads to decide whether to cut the climb clip before
	# its stand-up half. The number of frames it keeps is an eye value and is
	# not pinned here; WHETHER it cuts is not.
	var bits: Array = await _mantling_player(1.278)
	var grab: GrabMove = bits[1]
	assert_true(grab.is_mantling(), "the fixture never started a pull-up")
	assert_true(grab.is_climbing_low(), \
		"a climb into a 1.28 m opening was reported as having room to stand")

func test_a_climb_into_open_sky_is_not_reported_as_low() -> void:
	# The control: cutting every climb short would be worse than cutting none.
	var bits: Array = await _mantling_player()
	var grab: GrabMove = bits[1]
	assert_true(grab.is_mantling(), "the fixture never started a pull-up")
	assert_false(grab.is_climbing_low(), "an open ledge was treated as a duct")
