extends ParkourTest

# The reach that could never arrive, and the soft lock it caused.
#
# A ledge was committed to whenever it was within IntoGrabConfig's
# max_reach_distance (0.8 m), but contact needed the body's centre inside
# Move.contact_reach() -- about 0.48 m standing still. The approach phase moves
# the body not at all, so anything committed in that band kept its gap for the
# whole 1.5 s max_duration, handed back to Falling, waited out the 0.3 s
# cooldown and committed again on a ledge that had not moved. The player has no
# control during a reach, so that is a soft lock, not a flutter.
#
# THE GEOMETRY IS main.tscn's ShimmyArea/OuterBlock, moved to the origin: a
# 6 x 2.7 x 6 block with a 5 x 1.5 x 5 cap, which is what leaves the shimmy lip.
# The owner reproduced it there and the angles below are the ones reported.
#
# The probe measures along the LOOK direction, so turning the view lengthens
# the same physical gap -- which is why this reads as an angle window (34 to 59
# degrees off square) when it is really a distance band. Standing 0.8 m out and
# looking straight at the wall does it too.

const TestWorld = preload("res://tests/world_fixture.gd")

## Facing the -X face of the block square on.
const SQUARE_YAW := -PI * 0.5

var _world: Dictionary = {}

func after_each() -> void:
	for key in ["block", "cap"]:
		if _world.has(key) and is_instance_valid(_world[key]):
			_world[key].queue_free()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _slab(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = at
	return body

## `out` is how far the body stands from the block's -X face, `off` how far its
## view is turned from square, in radians.
func _beside_the_block(out: float, off: float) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	_world["block"] = _slab(Vector3(6.0, 2.7, 6.0), Vector3(0.0, 1.35, 0.0))
	_world["cap"] = _slab(Vector3(5.0, 1.5, 5.0), Vector3(0.0, 3.45, 0.0))
	var player: Player = _world["player"]
	player.global_position = Vector3(-3.0 - out, 0.95, -1.4)
	await step(20)
	player.rotation.y = SQUARE_YAW + off
	await step(5)
	return player

## How many separate reaches were committed over `ticks`, and what the body was
## doing at the end of them.
func _count_reaches(player: Player, ticks: int) -> Dictionary:
	var entries := 0
	var last: StringName = player.move_manager.current_name
	for _i in ticks:
		await step(1)
		var now: StringName = player.move_manager.current_name
		if now != last:
			last = now
			if last == Move.INTO_GRAB:
				entries += 1
	return {"entries": entries, "final": last}

func test_a_standing_jump_in_the_dead_band_commits_to_nothing() -> void:
	# 0.8 m out and looking straight at it -- the owner's own second repro, and
	# the one that shows the window was never about the angle.
	var player: Player = await _beside_the_block(0.8, 0.0)
	_world["input"].press_jump()
	var seen: Dictionary = await _count_reaches(player, 180)
	assert_eq(seen["entries"], 0,
		"a standing jump committed to a reach it could never complete")
	assert_eq(seen["final"], Move.WALKING,
		"the body never got back to walking (got %s)" % seen["final"])

func test_a_tap_toward_the_wall_does_not_buy_a_whole_reach() -> void:
	# THE HOLE IN THE FIRST VERSION OF THIS GUARD, found by the owner: gating
	# only the commit lets one tap of the stick through, and by the next tick
	# the body is drifting nowhere again -- with the reach already started and
	# 1.5 s of no control ahead of it. The approach has to keep asking.
	var player: Player = await _beside_the_block(0.5, deg_to_rad(44.0))
	_world["input"].press_jump()
	await step(6)
	_world["input"].hold_move(0.0, 1.0)
	await step(2)
	_world["input"].hold_move(0.0, 0.0)
	var seen: Dictionary = await _count_reaches(player, 180)
	assert_lte(seen["entries"], 1,
		"one tap toward the wall bought %d reaches" % seen["entries"])
	assert_eq(seen["final"], Move.WALKING,
		"the body never got back to walking (got %s)" % seen["final"])
