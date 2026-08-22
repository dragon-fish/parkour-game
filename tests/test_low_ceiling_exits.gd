extends ParkourTest

# A move that ends somewhere a standing body does not fit must hand off to
# CROUCH.
#
# ✅ Three bugs the owner found in one sitting, and they are one bug wearing
# three hats:
#
#   "滑铲结束如果头顶空间不够应该转下蹲而不是滑铲，否则玩家的左右会一直被牵制，
#    可能卡住出不来"
#   "落地翻滚如果碰巧滚进头顶空间不够的地方也应该转下蹲而不是 walk，否则会以蹲姿
#    跑出 7.2 的超高速度"
#
# request_standing_capsule() is a REQUEST -- Player owes the restore and pays it
# on the first tick there is room. That is the right contract, and it is exactly
# what makes the wrong hand-off invisible: nothing errors, nothing snaps, the
# player simply ends up in a state whose assumptions no longer hold. Walking
# assumes a standing body and runs at standing speed. A slide assumes it is
# still going somewhere and steers like it.
#
# Crouch is free from all three: crouch_capsule_height (0.9) is the same number
# as slide_capsule_height, and SkillRollMove.enter() shrinks to the crouch
# height by name. The hand-off changes no geometry at all -- only who owns the
# body.

const TestWorld = preload("res://tests/world_fixture.gd")

## Low enough that a 1.8 m capsule does not fit under it and a 0.9 m one does.
const CEILING_CLEARANCE := 1.2

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

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## A slab hanging over the player, leaving CEILING_CLEARANCE beneath it.
func _roof_over(player: Player) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.5, 8.0)
	shape.shape = box
	body.add_child(shape)
	player.get_parent().add_child(body)
	var feet: float = player.global_position.y - player.current_capsule_height() * 0.5
	body.global_position = Vector3(player.global_position.x,
			feet + CEILING_CLEARANCE + 0.25, player.global_position.z)
	_extra.append(body)
	return body

func _hold(crouch: bool = false) -> MoveInput:
	var input := MoveInput.new()
	input.crouch_held = crouch
	return input

func test_the_fixture_roof_really_does_block_standing() -> void:
	# Without this the three tests below would all pass on a roof that was never
	# in the way, and would be pinning nothing at all.
	var player: Player = await _player()
	_roof_over(player)
	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	await step(2)
	assert_false(player.has_headroom(),
		"the roof left room to stand, so these tests prove nothing")

# --- the slide ----------------------------------------------------------------

func test_a_slide_that_runs_out_under_a_roof_becomes_a_crouch() -> void:
	# It used to return KEEP and go on sliding. A slide commits you to a line --
	# steering is deliberately slow -- so a slide that cannot end is a slide you
	# cannot steer out of, and under a long low ceiling there is no input that
	# escapes it.
	var player: Player = await _player()
	_roof_over(player)
	player.move_manager.start(Move.SLIDE)
	# A tick BEFORE asking anything: enter() has just resized the capsule, and
	# has_headroom() reads the physics server, which has not seen that yet on
	# the tick it happened. Every test in this file that skipped this step
	# reported "no headroom" in open air.
	await step(2)
	var slide := player.move_manager.move_for(Move.SLIDE)
	# Spent: below slide_abort_speed, and the key let go.
	player.velocity = Vector3.ZERO
	var result: StringName = slide.physics_update(1.0 / 60.0, _hold(false))
	assert_eq(result, Move.CROUCH,
		"a spent slide under a roof returned %s" % result)

func test_a_slide_that_runs_out_in_the_open_still_stands_up() -> void:
	# The pair. Without it the test above passes on a build that sends every
	# slide to Crouch and never lets anyone stand again.
	var player: Player = await _player()
	player.move_manager.start(Move.SLIDE)
	# A tick BEFORE asking anything: enter() has just resized the capsule, and
	# has_headroom() reads the physics server, which has not seen that yet on
	# the tick it happened. Every test in this file that skipped this step
	# reported "no headroom" in open air.
	await step(2)
	var slide := player.move_manager.move_for(Move.SLIDE)
	player.velocity = Vector3.ZERO
	var result: StringName = slide.physics_update(1.0 / 60.0, _hold(false))
	assert_eq(result, Move.WALKING,
		"a spent slide in the open returned %s" % result)

# --- the roll ------------------------------------------------------------------

func test_a_roll_that_ends_under_a_roof_becomes_a_crouch() -> void:
	# ⚠️ THE EXPENSIVE ONE. A roll carries real speed and travels while it
	# plays, so where it ENDS is nowhere anyone chose. Handed to Walking, the
	# standing capsule it asks for will not fit, the request is deferred, and
	# the player runs at full speed in a crouched body -- the 7.2 m/s the owner
	# measured.
	var player: Player = await _player()
	_roof_over(player)
	player.move_manager.start(Move.SKILL_ROLL)
	await step(2)
	var roll := player.move_manager.move_for(Move.SKILL_ROLL)
	player.set_grounded(true)
	# Past its own duration, so this tick is the hand-off.
	var result: StringName = roll.physics_update(
		player.config.skill_roll.duration + 1.0, _hold(false))
	assert_eq(result, Move.CROUCH, "a roll ending under a roof returned %s" % result)

func test_a_roll_that_ends_in_the_open_still_stands_up() -> void:
	var player: Player = await _player()
	player.move_manager.start(Move.SKILL_ROLL)
	await step(2)
	var roll := player.move_manager.move_for(Move.SKILL_ROLL)
	player.set_grounded(true)
	var result: StringName = roll.physics_update(
		player.config.skill_roll.duration + 1.0, _hold(false))
	assert_eq(result, Move.WALKING, "a roll ending in the open returned %s" % result)
