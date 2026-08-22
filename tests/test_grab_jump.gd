extends ParkourTest

# Leaving a ledge by shoving off it.
#
# ✅ THE OWNER: "我们没有做 Grab 的回头跳，Grab 期间扭头超过 90 度就可以跳了,
# 力度跟踢墙跳比较类似." The original splits one key two ways on the same angle --
# TdMove_GrabJump.GrabAllowedJumpAngle = 45 against
# TdMove_GrabPullUp.GrabAllowedPullUpAngle = 45 -- so looking at the wall climbs
# it and looking away from it leaves it. The threshold here is the CDO's 45
# rather than the reported 90, at the owner's own direction: "有实测数据就按数据
# 来，我只能用手感跟你描述."
#
# 📌 And the comparison they drew holds for exactly half of it. Horizontally the
# shove is 2 to 4 m/s against the wall kick's own 3.0, so "similar" is right.
# Vertically the kick goes up at 5.8 and this goes up at 1.6. Letting go of a
# ledge drops you; it is not a boost.

const TestWorld = preload("res://tests/world_fixture.gd")

const LEDGE_TOP := 2.0
const LEDGE_FACE_Z := -1.5
const EDGE := Vector3(0.0, LEDGE_TOP, -1.6)
## Points away from the wall, back at the player -- so a push off the wall is
## along +Z here.
const FACE_NORMAL := Vector3(0.0, 0.0, 1.0)
const TOP_NORMAL := Vector3(0.0, 1.0, 0.0)

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A player hanging on a wall whose face normal is +Z, turned `yaw_deg` off
## looking straight at it.
func _hanging_player(yaw_deg: float) -> Player:
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
	# rotation.y = 0 faces -Z, which is straight into this wall.
	player.rotation.y = deg_to_rad(yaw_deg)
	var query := {"valid": true, "edge": EDGE, "top": EDGE,
			"normal": TOP_NORMAL, "face_normal": FACE_NORMAL}
	# Through IntoGrabMove.hanging_pose() rather than a hand-picked offset --
	# see the same note in test_ledge_shimmy.gd. A made-up pose is the one place
	# a standing capsule fits, and the game never puts the body there.
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.pending_ledge = query
	player.move_manager.start(Move.GRAB)
	await step(1)
	return player

func _grab(player: Player) -> GrabMove:
	return player.move_manager.move_for(Move.GRAB) as GrabMove

func _jump() -> MoveInput:
	var input := MoveInput.new()
	input.jump_pressed = true
	return input

func _config() -> GrabConfig:
	return MovementConfig.new().grab

# --- which half of the key you get -------------------------------------------

func test_jumping_while_facing_the_wall_still_climbs() -> void:
	# The behaviour that already existed, and the thing most at risk: the new
	# branch takes jump_pressed and is asked FIRST, so getting its condition
	# wrong silently replaces the pull-up rather than adding to it.
	var player: Player = await _hanging_player(0.0)
	var grab := _grab(player)
	var result: StringName = grab.physics_update(1.0 / 60.0, _jump())
	assert_ne(result, Move.FALLING, "jumping at the wall left the ledge")
	assert_true(grab.is_mantling(), "jumping at the wall did not start a pull-up")

func test_a_small_turn_still_climbs() -> void:
	# Just inside the allowed angle. The pair with the test below is what pins
	# the threshold to a number rather than to "some turn".
	var player: Player = await _hanging_player(_config().jump_angle_deg - 5.0)
	var grab := _grab(player)
	var result: StringName = grab.physics_update(1.0 / 60.0, _jump())
	assert_ne(result, Move.FALLING,
		"a %.0f degree turn left the ledge" % (_config().jump_angle_deg - 5.0))

func test_turning_past_the_angle_leaves_the_ledge() -> void:
	var player: Player = await _hanging_player(_config().jump_angle_deg + 5.0)
	var result: StringName = _grab(player).physics_update(1.0 / 60.0, _jump())
	assert_eq(result, Move.FALLING,
		"a %.0f degree turn did not leave the ledge" % (_config().jump_angle_deg + 5.0))

func test_the_angle_is_symmetric() -> void:
	# Turning the other way is the same turn. angle_to() is unsigned, which is
	# what makes this free -- but free is not the same as tested.
	var player: Player = await _hanging_player(-(_config().jump_angle_deg + 5.0))
	var result: StringName = _grab(player).physics_update(1.0 / 60.0, _jump())
	assert_eq(result, Move.FALLING, "turning left did not leave the ledge")

# --- where it sends you -------------------------------------------------------

func test_the_shove_is_away_from_the_wall_not_along_the_view() -> void:
	# ⚠️ THE ONE THAT MATTERS, and the threshold is what forces it: at the 45
	# degrees that first allows this jump, the view is still pointed half-way
	# INTO the wall, so pushing along the view would drive the body through the
	# thing it is hanging from. Turned a full 90 degrees the two answers are
	# perpendicular, so this cannot pass by coincidence.
	var player: Player = await _hanging_player(90.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	assert_gt(player.velocity.z, 0.5,
		"the shove went (%.2f, %.2f, %.2f) rather than away from the wall"
		% [player.velocity.x, player.velocity.y, player.velocity.z])
	assert_almost_eq(player.velocity.x, 0.0, 0.01,
		"the shove followed the view: x came out %.2f" % player.velocity.x)

func test_the_rise_is_a_shove_not_a_boost() -> void:
	var player: Player = await _hanging_player(180.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	assert_almost_eq(player.velocity.y, _config().jump_speed_up, 0.01,
		"went up at %.2f m/s instead of %.2f"
		% [player.velocity.y, _config().jump_speed_up])
	# And the comparison the owner drew, from the other side: this is nowhere
	# near the wall kick's 5.8 up, however close the horizontals are.
	assert_lt(player.velocity.y, 3.0, "a hang jump launched like a wall kick")

func test_a_bare_turn_shoves_least_and_a_full_turn_most() -> void:
	# ⚠️ The lerp between GrabJumpPushAwayMinSpeed and MaxSpeed is INFERRED --
	# the CDO gives both numbers and no driver, and the turn angle is the only
	# thing this move has that varies continuously. What is pinned here is the
	# two ENDS, which are sourced, plus the direction of travel between them.
	var cfg := _config()
	var player: Player = await _hanging_player(cfg.jump_angle_deg + 0.5)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	var least: float = player.velocity.z
	assert_almost_eq(least, cfg.jump_push_min, 0.1,
		"the smallest allowed turn shoved at %.2f instead of %.2f"
		% [least, cfg.jump_push_min])
	after_each()

	player = await _hanging_player(180.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	assert_almost_eq(player.velocity.z, cfg.jump_push_max, 0.1,
		"a full turn shoved at %.2f instead of %.2f"
		% [player.velocity.z, cfg.jump_push_max])
	assert_gt(player.velocity.z, least, "turning further did not shove harder")

# --- and it lets go properly ---------------------------------------------------

func test_leaving_this_way_asks_for_the_capsule_back_and_waits_for_room() -> void:
	# exit() runs on every way out, and this is a new one. But what it does is
	# REQUEST a standing capsule, not restore one -- Player owes the restore and
	# performs it on the first tick there is room.
	#
	# ⚠️ AND AT A HANG THERE IS NO ROOM, which is the whole finding of this
	# pass: the hanging body is 0.05 m through the wall face and 0.09 m above the
	# lip, so a standing capsule does not fit where the hang leaves it. The
	# restore is therefore correctly DEFERRED at the instant of the jump, and
	# lands once the shove has carried the body clear.
	#
	# An earlier version of this test placed the body by hand somewhere it did
	# fit, saw an immediate restore, and would have gone on passing over a real
	# regression here.
	var player: Player = await _hanging_player(180.0)
	var standing: float = player.current_capsule_height()
	var folded: float = MovementConfig.new().crouch.crouch_capsule_height
	player.set_capsule_height(folded)
	var grab := _grab(player)
	grab.physics_update(1.0 / 60.0, _jump())
	grab.exit()
	await step(3)
	assert_almost_eq(player.current_capsule_height(), folded, 0.001,
		"the body stood up while still inside the ledge")

	# Carried clear by the shove it was just given.
	player.global_position += Vector3(0.0, 0.0, 3.0)
	await step(3)
	assert_almost_eq(player.current_capsule_height(), standing, 0.001,
		"the body never got its height back after clearing the ledge")
