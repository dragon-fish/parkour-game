extends ParkourTest

# Rounding a ninety-degree corner while hanging.
#
# ✅ THE OWNER: "把内外九十度转角也做几个，这个在 ME 的教程关就出现了，肯定要做的",
# and later, timing it: "外 90 转角好像大概 1s 转过去，期间锁镜头，可能是怕穿帮."
#
# 🎯 THE TWO CORNERS ARE THE SHIMMY'S TWO REFUSALS. Ordinary travel already had
# to ask two questions -- is the ledge still there, is there room for the body --
# and each of them was a dead stop. An OUTSIDE corner is the first one failing
# with a perpendicular face beyond it; an INSIDE corner is the second one, where
# the thing blocking the way sideways turns out to be somewhere to go. Nothing
# new is detected here; the same two probes now have a second answer.

const TestWorld = preload("res://tests/world_fixture.gd")

## Tops at y = 2, which is what every structure in this file shares.
const TOP := 2.0
const MARGIN := 0.1

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

func _fresh() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

func _block(player: Player, centre: Vector3, size: Vector3) -> StaticBody3D:
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

## Hangs the player on `edge` with `normal` as the face, through the same
## function the game places a real grab with.
func _hang(player: Player, edge: Vector3, normal: Vector3) -> GrabMove:
	var query := {"valid": true, "edge": edge, "top": edge,
			"normal": Vector3.UP, "face_normal": normal}
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.rotation.y = atan2(normal.x, normal.z)
	player.pending_ledge = query
	player.move_manager.start(Move.GRAB)
	return player.move_manager.move_for(Move.GRAB) as GrabMove

func _hold(sideways: float) -> MoveInput:
	var input := MoveInput.new()
	input.move = Vector2(sideways, 0.0)
	return input

## Drives the move until it starts a corner, or gives up. Returns whether one
## started. Travelling is deliberately done in real steps rather than one big
## delta: the probes fire from wherever the hands have actually got to.
func _travel_until_corner(grab: GrabMove, side: float, ticks: int = 240) -> bool:
	for i in ticks:
		grab.physics_update(1.0 / 60.0, _hold(side))
		if grab.is_cornering():
			return true
	return false

# --- the outside corner --------------------------------------------------------

## A 4 m square block: south face at z = 0, east face at x = 2, top at y = 2.
func _square(player: Player) -> void:
	_block(player, Vector3(0.0, TOP * 0.5, -2.0), Vector3(4.0, TOP, 4.0))

func test_travelling_off_the_end_of_a_face_rounds_the_corner() -> void:
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	# On the south face, a little short of the south-east corner.
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0),
		"the hands reached the corner and stopped instead of going round it")

func test_the_corner_lands_the_body_on_the_perpendicular_face() -> void:
	# ⚠️ WHERE IT ENDS UP IS THE WHOLE POINT. A corner that plays its animation
	# and leaves the anchor on the old face has moved the body somewhere the
	# pull-up would launch from wrongly.
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0), "no corner started")
	# Past its own duration.
	for i in 90:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if not grab.is_cornering():
			break
	assert_false(grab.is_cornering(), "the corner never finished")
	# The east face's normal is +X, and the body should now be outside it.
	assert_almost_eq(grab._face_normal.x, 1.0, 0.05,
		"the face came out as %s instead of +X" % grab._face_normal)
	assert_gt(player.global_position.x, 2.0,
		"the body finished at x %.2f, still inside the block's east face"
		% player.global_position.x)

func test_the_corner_takes_the_time_the_owner_measured() -> void:
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0), "no corner started")
	var elapsed: float = 0.0
	for i in 200:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if not grab.is_cornering():
			break
		elapsed += 1.0 / 60.0
	assert_almost_eq(elapsed, player.config.grab.corner_duration, 0.05,
		"the corner took %.2f s against a configured %.2f"
		% [elapsed, player.config.grab.corner_duration])

func test_the_end_of_a_free_standing_wall_is_a_real_corner() -> void:
	# 📌 WRITTEN THE OTHER WAY ROUND FIRST, asserting that a wall simply ends --
	# and that was a wrong premise rather than a bug. A box has six faces: the
	# end of a 1 m deep wall IS a perpendicular face a metre wide, and swinging
	# onto it is a corner like any other. Ledges wrap around wall ends in the
	# original too.
	#
	# What keeps corners from being INVENTED is not "is this a wall end" but the
	# two checks that follow: the new face must be turned at least sixty degrees
	# from the old one, and its top must be at this ledge's height. The pillar
	# test below is the pin for the second, which is the one that does the work.
	var player: Player = await _fresh()
	_block(player, Vector3(0.0, TOP * 0.5, -0.5), Vector3(4.0, TOP, 1.0))
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0),
		"the hands stopped at the end of a wall that has a metre-wide end face")

# --- the inside corner ---------------------------------------------------------

func test_running_into_a_perpendicular_wall_turns_onto_it() -> void:
	var player: Player = await _fresh()
	# Along X, its south face at z = 0.
	_block(player, Vector3(-2.0, TOP * 0.5, -0.2), Vector3(4.0, TOP, 0.4))
	# Standing across the way, presenting a west face at x = 0.2 and reaching
	# out past the hanging body so the shoulder meets it.
	_block(player, Vector3(0.4, TOP * 0.5, 1.3), Vector3(0.4, TOP, 3.4))
	await step(2)
	var grab := _hang(player, Vector3(-1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0),
		"the body stopped at the inside corner instead of turning onto it")
	for i in 90:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if not grab.is_cornering():
			break
	assert_almost_eq(grab._face_normal.x, -1.0, 0.05,
		"the face came out as %s instead of -X" % grab._face_normal)

func test_a_pillar_with_no_ledge_is_just_an_obstacle() -> void:
	# ⚠️ THE ONE THAT KEEPS THE INSIDE CORNER HONEST. "Something is in the way"
	# is not the same as "somewhere to go": a pillar, a doorway reveal or a
	# parapet returning at the wrong height all block the hands while offering
	# no ledge at this height. The height check is the only thing separating
	# them, so it needs its own pin.
	var player: Player = await _fresh()
	_block(player, Vector3(-2.0, TOP * 0.5, -0.2), Vector3(4.0, TOP, 0.4))
	# Same footprint as the wall above, but TALL -- its top is nowhere near the
	# ledge the body is hanging from.
	_block(player, Vector3(0.4, TOP * 1.5, 1.3), Vector3(0.4, TOP * 3.0, 3.4))
	await step(2)
	var grab := _hang(player, Vector3(-1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_false(_travel_until_corner(grab, 1.0),
		"the body turned onto a wall whose top is a storey above the ledge")

# --- what a corner refuses -------------------------------------------------------

func test_a_corner_cannot_be_pulled_up_out_of_halfway_round() -> void:
	# A pull-up begun mid-corner would launch from a position that is neither
	# the ledge left nor the ledge arrived at.
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0), "no corner started")
	var climb := MoveInput.new()
	climb.move = Vector2(0.0, 1.0)
	climb.jump_pressed = true
	var result: StringName = grab.physics_update(1.0 / 60.0, climb)
	assert_ne(result, Move.FALLING, "a jump mid-corner left the ledge")
	assert_false(grab.is_mantling(), "a pull-up started halfway round a corner")
	assert_true(grab.is_cornering(), "the corner was abandoned")

func test_the_shimmy_is_refused_for_a_moment_after_a_corner() -> void:
	# ✅ DisableShimmyTime = 0.6. A corner leaves the hands a hand's width from
	# the corner they just rounded, so without a pause a wobble on the stick
	# walks them straight back around it.
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0), "no corner started")
	for i in 90:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if not grab.is_cornering():
			break
	assert_false(grab.is_cornering(), "the corner never finished")
	var settled: Vector3 = player.global_position
	# Well inside corner_lockout.
	grab.physics_update(0.1, _hold(1.0))
	assert_almost_eq(player.global_position.distance_to(settled), 0.0, 0.001,
		"the hands travelled %.3f m during the lockout"
		% player.global_position.distance_to(settled))
