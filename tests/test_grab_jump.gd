extends ParkourTest

# Leaving a ledge by shoving off it. Grab has no turn-around jump of its own;
# turning far enough away from the wall while hanging lets you jump instead,
# with force similar to a wall kick.
#
# [ME:CONFIRMED 05 §5.8] The original splits one key two ways on the same
# angle -- TdMove_GrabJump.GrabAllowedJumpAngle = 45 against
# TdMove_GrabPullUp.GrabAllowedPullUpAngle = 45 -- so looking at the wall
# climbs it and looking away from it leaves it. The threshold used here is
# this confirmed 45, not a felt estimate: measured data overrides feel
# whenever the two conflict.
#
# The wall-kick comparison holds for exactly half of it. [ME:CONFIRMED 05
# §5.8] Horizontally the shove is 2 to 4 m/s (GrabJump's own PushAwayMax/Min)
# against [ME:CONFIRMED 04 §4.3] the wall kick's own 3.0, so "similar" is
# right. Vertically [ME:CONFIRMED 04 §4.3] the kick goes up at 5.8 and this
# goes up at only 1.6. Letting go of a ledge drops you; it is not a boost.

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
	# jump_pressed is checked FIRST, ahead of the pull-up branch, so getting
	# its condition wrong silently replaces the pull-up rather than adding to
	# it.
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
	# The launch must go toward the VIEW direction, not along PushAway (the
	# original CDO field name): a hang jump that cannot carry you anywhere
	# makes a class of the original's level geometry unbuildable.
	#
	# BOTH READINGS ARE DEFENSIBLE ON THEIR OWN. The fields are named
	# PushAway, and at the 45 degrees this jump is first allowed the view
	# still points half INTO the wall, so launching straight along it would
	# drive the body through what it is hanging from. What settles it is the
	# design argument above; the wall is handled by projecting the
	# into-the-wall component out, not by refusing to look there.
	#
	# Turned a full 90 degrees, so "along the view" and "away from the wall"
	# are perpendicular and this cannot pass by coincidence.
	var player: Player = await _hanging_player(90.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	# Facing -X at yaw 90.
	assert_lt(player.velocity.x, -3.0,
		"the launch went (%.2f, %.2f, %.2f) rather than along the view"
		% [player.velocity.x, player.velocity.y, player.velocity.z])

func test_a_bare_turn_throws_you_at_your_own_ledge() -> void:
	# THE SPEEDRUN TECHNIQUE, and it is the reason nothing is projected out of
	# the launch. See GrabMove._launch_direction(): turning just past the
	# threshold and jumping AT the ledge converts the very slow GrabPullUp
	# into a VaultOver, and that conversion IS the into-the-wall component --
	# the body is thrown at its own lip and the airborne vault probe catches
	# the top on the way past.
	#
	# DO NOT clamp the launch to never point into the wall. That reads as
	# ordinary prudence but deletes this technique outright.
	var player: Player = await _hanging_player(_config().jump_angle_deg + 1.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	# The wall's outward normal is +Z here, so INTO it is negative z.
	assert_lt(player.velocity.z, -1.0,
		"a jump one degree past the threshold went (%.2f, %.2f, %.2f) rather than at the ledge"
		% [player.velocity.x, player.velocity.y, player.velocity.z])

func test_it_is_a_jump_rather_than_a_shove() -> void:
	# The launch must read as a JUMP, not a limp drop. [ME:CONFIRMED 02 §2.4]
	# base_jump_z is 6.3, matching [ME:DERIVED 04 §4.3] the wall kick's own
	# combined magnitude of about 6.6 (sqrt(3.0^2 + 5.8^2)).
	var player: Player = await _hanging_player(180.0)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	assert_gt(player.velocity.length(), _config().jump_speed - 0.5,
		"launched at %.2f m/s, which is not a jump" % player.velocity.length())

func _incline_of(v: Vector3) -> float:
	return rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))

## The launch off a hang with the view pitched `pitch_deg` (positive up).
func _launch_pitched(pitch_deg: float) -> Vector3:
	var player: Player = await _hanging_player(180.0)
	player.camera_rig.set_pitch(deg_to_rad(pitch_deg))
	await step(2)
	_grab(player).physics_update(1.0 / 60.0, _jump())
	var launch := player.velocity
	after_each()
	return launch

func test_a_level_or_lowered_view_launches_at_the_floor_incline() -> void:
	# Having to look up for every jump was the complaint: at or below the
	# floor, the pitch changes nothing.
	var floor_deg := _config().jump_min_pitch_deg
	for pitch_deg in [0.0, -35.0]:
		var launch: Vector3 = await _launch_pitched(pitch_deg)
		assert_almost_eq(_incline_of(launch), floor_deg, 1.0,
			"a view pitched %+.0f launched at %.1f degrees" % [pitch_deg, _incline_of(launch)])

func test_looking_higher_than_the_floor_launches_higher() -> void:
	# A fixed incline left some jumps short: above the floor, the view wins.
	var launch: Vector3 = await _launch_pitched(60.0)
	assert_almost_eq(_incline_of(launch), 60.0, 1.5,
		"a view pitched up 60 launched at %.1f degrees" % _incline_of(launch))

# --- and it lets go properly ---------------------------------------------------

func test_leaving_this_way_asks_for_the_capsule_back_and_waits_for_room() -> void:
	# exit() must REQUEST a standing capsule, not restore one on the spot --
	# Player owes the restore and performs it on the first tick there is room.
	#
	# AT A HANG THERE IS NO ROOM: the hanging body is 0.05 m through the wall
	# face and 0.09 m above the lip, so a standing capsule does not fit where
	# the hang leaves it. The restore is therefore correctly DEFERRED at the
	# instant of the jump, landing once the shove has carried the body clear.
	#
	# DO NOT place the body by hand somewhere a standing capsule already fits
	# -- that hides an immediate, incorrect restore and passes over this exact
	# regression.
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
	# Past the pull-up angle, W must not trigger GrabUp. [ME:INFERRED] The
	# original gates it the same way, because a player turning to jump away
	# usually presses W and space together, and W must not steal that as a
	# climb.
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
	# THE GESTURE THAT MAKES THE GATE NECESSARY: a player turning to jump away
	# naturally presses W and jump together. Jump must win that race, or the
	# hang jump stays unreachable in practice however correct it is in
	# isolation.
	var player: Player = await _hanging_player(180.0)
	var grab := _grab(player)
	var both := MoveInput.new()
	both.move = Vector2(0.0, 1.0)
	both.jump_pressed = true
	var result: StringName = grab.physics_update(1.0 / 60.0, both)
	assert_eq(result, Move.FALLING, "W and jump together climbed instead of jumping")
	assert_false(grab.is_mantling(), "a pull-up started on the jump tick")

# --- one press, one action ---------------------------------------------------
#
# [ME:INFERRED] In the original, one keypress corresponds to exactly one
# action. Player._tick_timers() arms the roll buffer on EVERY crouch_pressed,
# unconditionally -- including the very press that drops the body off this
# ledge. Left alone, that one press pays for both the drop and (for up to
# roll_trigger_time afterwards) a skill roll at whatever the fall turns out
# to be.

func test_the_drop_press_does_not_also_buy_a_roll_at_the_landing() -> void:
	var player: Player = await _hanging_player(0.0)
	# Same synthetic-launch trick test_skill_roll.gd's _land_from() uses: the
	# fixture's flat floor otherwise lands the body back at the exact height
	# FallTracker last zeroed at, which never clears the roll threshold and
	# would hide the bug regardless of whether it is fixed.
	player.fall_tracker.reset(player.global_position.y + player.config.pawn.skill_roll_landing_height + 0.5)
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()  # the one press: drops off the ledge
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "test setup: crouch did not drop from the hang")
	input.release_crouch()
	var saw_roll := false
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.SKILL_ROLL:
			saw_roll = true
		if player.grounded and player.move_manager.current_name != Move.SKILL_ROLL:
			break
	assert_false(saw_roll, "the same press that dropped the body also fired a skill roll")

func test_a_second_crouch_press_after_the_drop_still_buys_a_roll() -> void:
	# The counter-test: proves the fix above removes the DOUBLE billing only,
	# not the roll itself. A genuinely new press, thrown while already
	# falling, is its own action and must still buy one. Mirrors
	# test_zipline_move.gd's test_a_second_later_press_still_buys_a_roll.
	var player: Player = await _hanging_player(0.0)
	# Same synthetic-launch trick as the test above.
	player.fall_tracker.reset(player.global_position.y + player.config.pawn.skill_roll_landing_height + 0.5)
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()  # press #1: drops off the ledge
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "test setup: crouch did not drop from the hang")
	input.release_crouch()
	input.press_crouch()  # press #2: a new press, while already airborne
	var saw_roll := false
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.SKILL_ROLL:
			saw_roll = true
			break
	assert_true(saw_roll, "a second, later press did not buy a roll")
