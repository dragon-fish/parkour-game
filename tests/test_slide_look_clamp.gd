extends ParkourTest

# A slide's yaw fan is a TOTAL, not a per-tick rate.
#
# ✅ THE OWNER, in play: "I forgot the slide's yaw clamp -- it can still turn
# freely." Both halves of the measured pair were in the config and the yaw half
# did nothing: a RELATIVE look constraint is a per-tick rate limit by
# construction (CameraRig.apply_look says so in as many words), and +-54.9
# degrees PER FRAME is no limit at all.
#
# The number itself is confirmed -- 05 §5.1's MinLookConstraint
# (-10000, -10000, 0), UE3 integer angles at 65536 = 360, so +-54.9 on pitch
# AND yaw. Only its meaning was lost.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## Runs up and slides for real, the way test_slide.gd does. ⚠️ The first draft
## called move_manager.start(SLIDE) directly and the move bounced straight back
## to Walking, so the whole test measured an ordinary walk and reported it as a
## slide turning 756 degrees.
func _sliding_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	_world["input"].state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
	_world["input"].press_crouch()
	await step(2)
	var player: Player = _world["player"]
	assert_eq(player.move_manager.current_name, Move.SLIDE,
		"the fixture never entered a slide -- it is in %s" % player.move_manager.current_name)
	return player

## ⚠️ ACCUMULATED PER TICK, not measured end to end. A free look passes 180
## degrees within a few ticks of this drag, and wrapf() on the total then folds
## a full turn back to nearly nothing -- the first draft of this reported an
## unclamped WALK as having turned 36 degrees.
func _drag(player: Player, pixels: float, ticks: int) -> float:
	var total: float = 0.0
	for i in ticks:
		var before: float = player.rotation.y
		player.camera_rig.apply_look(Vector2(pixels, 0.0), player, 1.0 / 60.0)
		total += absf(wrapf(player.rotation.y - before, -PI, PI))
	return total

func test_a_slide_cannot_be_turned_all_the_way_round() -> void:
	# THE REPORTED BUG. Thirty ticks of a hard drag is far more than a fan of
	# 54.9 degrees, and used to be exactly thirty times the per-tick limit.
	var player: Player = await _sliding_player()
	var turned: float = _drag(player, 200.0, 30)
	assert_lt(turned, deg_to_rad(60.0),
		"a slide turned %.0f degrees" % rad_to_deg(turned))

func test_the_fan_is_the_measured_one_and_not_merely_small() -> void:
	# The pair: a clamp that let almost nothing through would pass the test
	# above and be just as wrong. The fan is 54.9 degrees, so most of it should
	# be reachable.
	var player: Player = await _sliding_player()
	var turned: float = _drag(player, 200.0, 30)
	assert_gt(turned, deg_to_rad(40.0),
		"a slide could only turn %.0f degrees" % rad_to_deg(turned))

func test_walking_is_not_clamped_at_all() -> void:
	# The control. SlideConfig declares the constraint; nothing should have
	# leaked onto the ordinary walk.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	await step(1)
	var turned: float = _drag(player, 200.0, 30)
	assert_gt(turned, deg_to_rad(90.0),
		"an ordinary walk only turned %.0f degrees" % rad_to_deg(turned))
