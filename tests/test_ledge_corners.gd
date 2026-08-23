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

# --- a ledge you can hang from but not climb onto ------------------------------

## The square, with a smaller block sitting on it: a rim too narrow to stand on,
## so the ledge can be hung from and not pulled up onto.
func _capped_square(player: Player) -> void:
	_square(player)
	# 3 m cap on a 4 m block leaves a 0.5 m rim -- narrower than the body, which
	# is 0.8 m across.
	_block(player, Vector3(0.0, TOP + 0.75, -2.0), Vector3(3.0, 1.5, 3.0))

func test_the_rim_really_is_too_narrow_to_pull_up_onto() -> void:
	# Without this the corner test below passes on geometry that was never
	# capped in the first place.
	var player: Player = await _fresh()
	_capped_square(player)
	await step(2)
	assert_false(player.fits_standing_at(Vector3(1.0, TOP, -MARGIN)),
		"the rim left room to stand, so this is not the case the owner hit")

func test_a_capped_ledge_still_rounds_its_corner() -> void:
	# ✅ THE OWNER, after the uncapped course worked: "我在 me_level0 里外转角失败了，
	# 感觉区别在那个地方不满足 climb_up 条件" -- a ledge you can hang from and not
	# climb onto. Hanging under an overhang and travelling to somewhere the slab
	# does not reach is the whole point of a shimmy, so a corner that only works
	# on open ledges works in the wrong half of the cases.
	var player: Player = await _fresh()
	_capped_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	assert_true(_travel_until_corner(grab, 1.0),
		"a capped ledge stopped at the corner")

func test_travelling_along_a_capped_ledge_works_at_all() -> void:
	# Asked separately, because if plain travel is what the cap breaks then the
	# corner never gets a chance and the test above would blame the wrong thing.
	var player: Player = await _fresh()
	_capped_square(player)
	await step(2)
	var grab := _hang(player, Vector3(0.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	var before: float = player.global_position.x
	for i in 20:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
	assert_gt(player.global_position.x, before + 0.05,
		"a capped ledge could not be travelled along at all")

func test_how_narrow_a_rim_a_corner_survives() -> void:
	# DIAGNOSTIC, not a requirement. The owner's me_level0 corner fails on
	# geometry a 0.5 m rim reproduces fine here, so this walks the rim in to
	# find where it does break -- both probes drop from LEDGE_ANCHOR_MARGIN
	# (0.1 m) inside the face, and a ray that starts inside a cap reports
	# nothing at all.
	for rim in [0.30, 0.15, 0.10, 0.05]:
		var player: Player = await _fresh()
		_square(player)
		var cap: float = 4.0 - rim * 2.0
		_block(player, Vector3(0.0, TOP + 0.75, -2.0), Vector3(cap, 1.5, cap))
		await step(2)
		var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
		var turned: bool = _travel_until_corner(grab, 1.0)
		gut.p("rim %.2f m -> corner %s" % [rim, "yes" if turned else "NO"])
		after_each()
	assert_true(true)

# --- the model comes round with the body ---------------------------------------

func test_the_visible_model_turns_with_the_corner() -> void:
	# ✅ THE OWNER: "转角的时候人物模型忘记转了，因为它被设计为 grab 时不转动."
	#
	# ⚠️ AND THE FREEZE IS RIGHT, WHICH IS WHY THIS NEEDED SAYING RATHER THAN
	# REMOVING. GrabConfig declares freeze_visual_yaw because a hanging body
	# cannot swivel its legs to follow the view, so _drive_body_yaw()
	# counter-rotates BodyRoot to hold the model's world yaw still however far
	# the collision body turns. A corner is the one time the body genuinely IS
	# turning, and the freeze cancelled every degree of it.
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	var before: float = player._visual_yaw
	assert_true(_travel_until_corner(grab, 1.0), "no corner started")
	for i in 90:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if not grab.is_cornering():
			break
	assert_false(grab.is_cornering(), "the corner never finished")
	var swept: float = absf(rad_to_deg(wrapf(player._visual_yaw - before, -PI, PI)))
	assert_almost_eq(swept, 90.0, 5.0,
		"the model swept %.1f degrees over a ninety-degree corner" % swept)

func test_hanging_still_does_not_turn_the_model() -> void:
	# The pair, and the behaviour the owner asked for in the first place:
	# looking around while hanging turns the head, not the body.
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	var before: float = player._visual_yaw
	for i in 30:
		grab.physics_update(1.0 / 60.0, _hold(0.0))
	assert_almost_eq(player._visual_yaw, before, 0.001,
		"the model turned %.2f degrees while hanging still"
		% rad_to_deg(player._visual_yaw - before))

func test_the_model_squares_up_to_the_new_face_however_it_arrived() -> void:
	# ✅ THE OWNER: "多转角几次身体模型就完全倒过来了."
	#
	# ⚠️ THE FIRST VERSION ADDED EACH TICK'S SLICE TO THE MODEL, which looks
	# equivalent to stating the answer and is not: the collision body's yaw is
	# REBUILT every tick as reference-plus-relative, and apply_look eases
	# `relative` whenever the fan moves out from under the view -- which is
	# exactly what a corner does to it. Two quantities maintained by different
	# arithmetic, and the gap survived each corner and stacked with the next.
	#
	# Pinned to the FACE instead, so a corner is self-correcting: start the
	# model anywhere and it comes out squared up to the wall it is now on.
	var player: Player = await _fresh()
	_square(player)
	await step(2)
	var grab := _hang(player, Vector3(1.0, TOP, -MARGIN), Vector3(0.0, 0.0, 1.0))
	# Deliberately wrong to begin with, by more than a corner is worth: this is
	# the accumulated drift the owner saw, injected in one go.
	player.pin_visual_yaw(deg_to_rad(150.0))
	assert_true(_travel_until_corner(grab, 1.0), "no corner started")
	for i in 90:
		grab.physics_update(1.0 / 60.0, _hold(1.0))
		if not grab.is_cornering():
			break
	assert_false(grab.is_cornering(), "the corner never finished")
	# The east face's normal is +X, so facing into it is atan2(1, 0) = 90.
	var facing: float = rad_to_deg(wrapf(player.visual_yaw()
		- atan2(grab._face_normal.x, grab._face_normal.z), -PI, PI))
	assert_almost_eq(absf(facing), 0.0, 2.0,
		"the model came out %.1f degrees off square to the face it is on" % facing)

# --- the owner's whitebox, to the centimetre -----------------------------------

## The eave corner from scenes/debug_levels/sandbox.tscn, group 转角挂边爬行,
## transcribed rather than approximated: the bug lived in three centimetres.
##
##   south eave  x[-6.048,-2.702] y[2.302,2.628] z[13.935,14.267]
##   west eave   x[-6.048,-5.711] y[2.302,2.628] z[14.264,16.847]
##   south fence z[13.974,14.007]   west fence x[-6.005,-5.943]
##
## Both fences stand ON their eave and run from below its top to well above head
## height, so the column each occupies is solid top to bottom.
const EAVE_TOP := 2.6282

func _owners_corner(player: Player) -> void:
	_block(player, Vector3(-4.374817, 2.465127, 14.100849),
			Vector3(3.3460693, 0.32617188, 0.33190918))
	_block(player, Vector3(-5.8793945, 2.465127, 15.555216),
			Vector3(0.33691406, 0.32617188, 2.5832214))
	_block(player, Vector3(-4.209198, 1.2798243, 15.536758),
			Vector3(3.0148315, 2.2768555, 2.5986938))
	_block(player, Vector3(-5.3278437, 3.785005, 13.990347),
			Vector3(1.3551693, 2.4624023, 0.032852173))
	_block(player, Vector3(-5.974084, 3.785005, 15.422159),
			Vector3(0.06268883, 2.4624023, 2.8506813))

func test_the_owners_corner_rounds_from_the_south_eave() -> void:
	# The direction that already worked: the south fence sits 0.039 m back from
	# its face, so the anchor's 0.100 m clears it.
	var player: Player = await _fresh()
	_owners_corner(player)
	await step(2)
	var grab := _hang(player, Vector3(-5.0, EAVE_TOP, 14.035),
			Vector3(0.0, 0.0, -1.0))
	assert_true(_travel_until_corner(grab, 1.0, 600),
		"the direction that already worked stopped working: %s" % grab.shimmy_report())

func test_the_owners_corner_rounds_from_the_west_eave() -> void:
	# ✅ THE REGRESSION: "从西边的屋檐可以去北边的屋檐，但是没办法爬回来."
	#
	# The west fence spans x[-6.005,-5.943] and the anchor lands at -5.948 --
	# INSIDE it. The down-probe therefore began inside solid geometry, and a ray
	# that starts inside reports nothing at all: indistinguishable, from the
	# probe's side, from "there is no ledge here". Three centimetres of level
	# editing is the whole difference between the two directions.
	var player: Player = await _fresh()
	_owners_corner(player)
	await step(2)
	var grab := _hang(player, Vector3(-5.948, EAVE_TOP, 15.5),
			Vector3(-1.0, 0.0, 0.0))
	var from_z: float = player.global_position.z
	var turned: bool = _travel_until_corner(grab, -1.0, 600)
	var travelled: float = from_z - player.global_position.z
	# ⚠️ THE DISTANCE, NOT MERELY "a corner happened". The first version of this
	# asserted only that is_cornering() went true, and it passed with the fix
	# reverted -- because a probe that fails on the FIRST tick drops straight
	# into the outside-corner branch and fires one on the spot, a metre and a
	# half short of the actual corner. "没办法爬回来" is travel failing, so
	# travel is what has to be measured.
	assert_gt(travelled, 1.0,
		"travelled only %.2f m along the west eave before stopping: %s"
		% [travelled, grab.shimmy_report()])
	assert_true(turned, "reached the corner and did not round it: %s"
		% grab.shimmy_report())

func test_the_west_anchor_really_is_inside_the_fence() -> void:
	# Without this the test above could pass on geometry that never reproduced
	# the problem -- which is what three earlier attempts at reproducing it did.
	var player: Player = await _fresh()
	_owners_corner(player)
	await step(2)
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(-5.948, EAVE_TOP + 0.3, 15.5),
			Vector3(-5.948, EAVE_TOP - 0.15, 15.5))
	# ⚠️ hit_from_inside, AND THE FIRST VERSION OF THIS TEST DID NOT SET IT --
	# it asserted the ray came back EMPTY and called that "clear". Empty means
	# either "nothing there" or "started inside something", and the second is
	# the entire mechanism under test. A control that cannot tell the bug from
	# its absence is not a control.
	query.hit_from_inside = true
	assert_false(space.intersect_ray(query).is_empty(),
		"the fixture's west anchor column is clear, so it is not the owner's case")
