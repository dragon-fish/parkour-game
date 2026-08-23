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

## Freed by after_each(): TestWorld.teardown() frees only the player and the
## floor, so a slab added beside them outlives its test -- see the same note in
## test_low_ceiling_exits.gd for what that cost.
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
	_extra.append(body)
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

func test_the_launch_follows_the_view() -> void:
	# ✅ THE OWNER, on the CDO-faithful first version: "grab 回头跳给的冲量不太对，
	# 应该是往镜头方向一个大跳."
	#
	# ⚠️ THIS TEST USED TO ASSERT THE OPPOSITE, and it was not wrong to: the
	# fields are named PushAway, and at the 45 degrees this jump is first
	# allowed the view still points half INTO the wall, so launching along it
	# would drive the body through what it is hanging from. Both remain true.
	# What settles it is the owner's design argument -- a hang jump that cannot
	# carry you anywhere makes a class of the original's level geometry
	# unbuildable -- and the wall is handled by projecting the into-the-wall
	# component out rather than by refusing to look there.
	#
	# Turned a full 90 degrees, so "along the view" and "away from the wall" are
	# perpendicular and this cannot pass by coincidence.
	var player: Player = await _hanging_player(90.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	# Facing -X at yaw 90.
	assert_lt(player.velocity.x, -3.0,
		"the launch went (%.2f, %.2f, %.2f) rather than along the view"
		% [player.velocity.x, player.velocity.y, player.velocity.z])

func test_a_bare_turn_throws_you_at_your_own_ledge() -> void:
	# THE SPEEDRUN GLITCH, and it is the reason nothing is projected out of the
	# launch. See GrabMove._launch_direction() for the owner's account: turning
	# just past the threshold and jumping AT the ledge converts the very slow
	# GrabPullUp into a VaultOver, and that conversion IS the into-the-wall
	# component -- the body is thrown at its own lip and the airborne vault
	# probe catches the top on the way past.
	#
	# THIS TEST REPLACES ONE ASSERTING THE OPPOSITE. The previous version
	# required the launch never to point into the wall, which read as ordinary
	# prudence and silently deleted a technique the speedrun route is built on.
	var player: Player = await _hanging_player(_config().jump_angle_deg + 1.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	# The wall's outward normal is +Z here, so INTO it is negative z.
	assert_lt(player.velocity.z, -1.0,
		"a jump one degree past the threshold went (%.2f, %.2f, %.2f) rather than at the ledge"
		% [player.velocity.x, player.velocity.y, player.velocity.z])

func test_it_is_a_jump_rather_than_a_shove() -> void:
	# ✅ "我们的实现就是软绵绵地落下来." The old numbers gave 2 to 4 m/s and then a
	# drop; base_jump_z is 6.3 and the wall kick's own magnitude is about 6.6.
	var player: Player = await _hanging_player(180.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	assert_gt(player.velocity.length(), _config().jump_speed - 0.5,
		"launched at %.2f m/s, which is not a jump" % player.velocity.length())

func test_looking_up_sends_you_up() -> void:
	# ✅ "如果抬头也会有往上的力." The pitch has to be in the launch direction,
	# which is why it is the full 3D look vector rather than its horizontal
	# shadow.
	#
	# Which way the pitch sign points is read off the CAMERA rather than assumed,
	# so this pins the behaviour and not a convention.
	var level: Player = await _hanging_player(180.0)
	_grab(level).physics_update(1.0 / 60.0, _jump())
	var flat_rise: float = level.velocity.y
	after_each()

	var player: Player = await _hanging_player(180.0)
	var rig = player.camera_rig
	assert_not_null(rig, "no camera rig to pitch")
	rig.set_pitch(deg_to_rad(35.0))
	await step(2)
	var looked_up: bool = (-rig.camera.global_transform.basis.z).y > 0.0
	_grab(player).physics_update(1.0 / 60.0, _jump())
	if looked_up:
		assert_gt(player.velocity.y, flat_rise + 1.0,
			"pitching the view up added only %.2f m/s of rise"
			% (player.velocity.y - flat_rise))
	else:
		assert_lt(player.velocity.y, flat_rise - 1.0,
			"pitching the view down did not take rise away (%.2f vs %.2f)"
			% [player.velocity.y, flat_rise])

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

# --- forward is gated by the same angle ----------------------------------------

func test_forward_pulls_up_while_facing_the_wall() -> void:
	var player: Player = await _hanging_player(0.0)
	var grab := _grab(player)
	var forward := MoveInput.new()
	forward.move = Vector2(0.0, 1.0)
	grab.physics_update(1.0 / 60.0, forward)
	assert_true(grab.is_mantling(), "forward at the wall did not pull up")

func test_forward_does_nothing_once_the_view_is_turned_away() -> void:
	# ✅ THE OWNER: "grab 期间如果镜头扭动超过 45°，按 W 就不要触发 GrabUp，ME 里也是
	# 这么处理的，因为玩家一般都是回头同时按 W+空格."
	var player: Player = await _hanging_player(_config().pull_up_angle_deg + 5.0)
	var grab := _grab(player)
	var forward := MoveInput.new()
	forward.move = Vector2(0.0, 1.0)
	var result: StringName = grab.physics_update(1.0 / 60.0, forward)
	assert_false(grab.is_mantling(),
		"forward pulled up with the view %.0f degrees off the wall"
		% (_config().pull_up_angle_deg + 5.0))
	assert_ne(result, Move.FALLING, "forward alone left the ledge")

func test_forward_and_jump_together_jumps_rather_than_climbs() -> void:
	# ⚠️ THE GESTURE THAT MADE THE GATE NECESSARY. Turned away and pressing both
	# -- which is what a player does -- used to hit the pull-up branch on the
	# same tick and win, so the hang jump was unreachable in practice however
	# correct it was in isolation.
	var player: Player = await _hanging_player(180.0)
	var grab := _grab(player)
	var both := MoveInput.new()
	both.move = Vector2(0.0, 1.0)
	both.jump_pressed = true
	var result: StringName = grab.physics_update(1.0 / 60.0, both)
	assert_eq(result, Move.FALLING, "W and jump together climbed instead of jumping")
	assert_false(grab.is_mantling(), "a pull-up started on the jump tick")
