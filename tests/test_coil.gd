extends ParkourTest

# Coil -- tucking the legs up in mid-air. GBA_Crouch's fifth outlet, and the
# last one this project had no code behind: walking_move.gd's own table
# comment used to end that row with "(OUT OF SCOPE, no such move)".
#
# WHAT IS PINNED HERE IS NOT THE NUMBERS. 0.9 m, 0.5 s and 0.25 s are dials
# (docs/feel-backlog.md 57) -- they will be turned, and a wrong one is visible
# at a glance. What these cases hold down is the handful of things that do not
# move when the feel is retuned:
#
#   * THE SHRINK IS ANCHORED AT THE CENTRE. ✅ The owner, reading ME Tweaks'
#     collision-box visualiser directly: "胶囊缩放不是以头为准！是以中心为准！
#     也就是说同时会增加头顶的空间". The feet rise by exactly as much as the
#     headroom grows. This is the ONLY thing separating a coil from a crouch,
#     which shrinks the same capsule to the same height anchored at the FEET.
#
#   * COIL RUNS NO PROBES. 11 §11.2's capability matrix gives Coil none of
#     bCheckForGrab / bCheckForVaultOver / bCheckForWallClimb -- it is one of
#     the few airborne states holding not one of the three. That is what makes
#     the manoeuvre risky, and it reads exactly like forgotten wiring, so it
#     is nailed down here rather than left to a config file nobody re-reads.
#
#   * THE CAPSULE COMES BACK, AND THE BODY IS NOT BURIED DOING SO. Growing a
#     centre-anchored capsule back to standing drops its floor by half the
#     shrink. player.gd's set_capsule_height() carries a warning about exactly
#     this failure -- an earlier crown-anchored option put half the character
#     underground, and the owner caught it in play.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

## Geometry these cases build by hand -- slabs and ceilings. Tracked so that
## after_each() can take it down.
##
## ⚠️ THE CASES USED TO FREE THEIR OWN, ON THE LAST LINE, and it cost a run:
## a case that FAILS never reaches its last line, so a failed assertion left a
## floor standing at chest height in the middle of the shared scene tree and
## the next file to run inherited it. That is what "1 failing test, but only in
## a full run" was. free(), not queue_free(), for the same reason -- a deferred
## release survives into the next test.
var _props: Array[Node] = []

func after_each() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			prop.free()
	_props.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A player already running, already airborne, and still inside Jump -- the
## only state a coil may be entered from.
func _jumping() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(30)
	_world["input"].state.move = Vector2(0.0, 1.0)
	await step(40)
	_world["input"].press_jump()
	await step(2)
	_world["input"].release_jump()
	return _world["player"]

## The capsule's own bottom and top, in the body's local space. Read through
## the collision node rather than derived from the height, because WHERE the
## shape sits relative to the origin is the entire subject of these tests.
func _capsule_span(player: Player) -> Vector2:
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	var centre: float = shape_node.position.y
	return Vector2(centre - capsule.height * 0.5, centre + capsule.height * 0.5)

# --- entry --------------------------------------------------------------------

func test_crouching_in_mid_air_enters_coil() -> void:
	var player: Player = await _jumping()
	assert_eq(player.move_manager.current_name, Move.JUMP, "test setup: not in Jump")
	assert_gt(player.horizontal_speed(), player.config.coil.min_trigger_speed,
		"test setup: too slow to be allowed a coil")

	_world["input"].press_crouch()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.COIL,
		"crouch in mid-air did not coil (got %s)" % player.move_manager.current_name)

func test_a_standing_jump_is_too_slow_to_coil() -> void:
	# ✅ 05 §5.2, measured in-game: a vertical jump with the crouch key pressed
	# does NOTHING. CoilMinTriggerSpeed = 100 uu/s = 1.0 m/s is that threshold,
	# and this is the row of the table that has no outlet at all.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(30)
	var player: Player = _world["player"]
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.JUMP, "test setup: not in Jump")
	assert_lt(player.horizontal_speed(), player.config.coil.min_trigger_speed,
		"test setup: the standing jump carried speed")

	_world["input"].press_crouch()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"a standing jump coiled when it should have done nothing")

func test_falling_cannot_coil() -> void:
	# ✅ The owner, measured: "实测只能Jump进入". 11.3's chart draws Jump -> Coil
	# and nothing else into it.
	#
	# This also happens to be what keeps a coil from eating the landing roll:
	# a player reaching for the crouch key on the way down to roll is already
	# past enter_to_falling_z_speed, so the press reaches settle_landing()'s
	# own consume_roll() rather than being spent here.
	var player: Player = await _jumping()
	for i in 200:
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING, "never reached Falling")

	_world["input"].press_crouch()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.FALLING,
		"a coil started from Falling (got %s)" % player.move_manager.current_name)

# --- the capsule ----------------------------------------------------------------

func test_the_coil_shrinks_the_capsule_about_its_centre() -> void:
	var player: Player = await _jumping()
	var standing := _capsule_span(player)

	_world["input"].press_crouch()
	# Past boost_duration, so the shrink has finished easing in.
	await step(20)
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: not coiled")

	var coiled := _capsule_span(player)
	var feet_rose: float = coiled.x - standing.x
	var headroom_gained: float = standing.y - coiled.y
	assert_gt(feet_rose, 0.01, "the coil did not lift the feet at all")
	assert_almost_eq(feet_rose, headroom_gained, 0.001,
		"the shrink is not centred: feet rose %.3f m but headroom grew %.3f m"
		% [feet_rose, headroom_gained])

func test_a_crouch_shrinks_the_same_capsule_from_the_feet() -> void:
	# The contrast case, and the reason the one above is worth a test: crouch
	# and coil reach the SAME height by different anchors, so a coil written
	# on top of set_capsule_height() would pass "the capsule got shorter" and
	# still be wrong.
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(30)
	var player: Player = _world["player"]
	var standing := _capsule_span(player)

	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	var crouched := _capsule_span(player)
	assert_almost_eq(crouched.x, standing.x, 0.001,
		"the crouch moved the feet, which is the coil's job and not its own")
	assert_lt(crouched.y, standing.y - 0.01, "the crouch did not lower the head")

func test_the_coil_keeps_the_capsule_until_the_landing() -> void:
	# [ME:CONFIRMED by the collision-box visualiser] the tuck ends at CoilTime,
	# the shrink does not: the rest of the flight is made half height.
	var player: Player = await _jumping()
	var standing := _capsule_span(player)

	_world["input"].press_crouch()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: not coiled")
	# Let go, or the landing's crouch holds the body down for the key.
	_world["input"].release_crouch()

	for i in 200:
		await step(1)
		if player.move_manager.current_name != Move.COIL:
			break
	assert_ne(player.move_manager.current_name, Move.COIL, "the coil never ended")
	await step(1)
	assert_false(player.grounded, "test setup: the coil ended on the ground")
	assert_lt(_capsule_span(player).y - _capsule_span(player).x, standing.y - standing.x - 0.1,
		"the capsule was given back in the air")

	for i in 200:
		await step(1)
		if player.grounded:
			break
	assert_true(player.grounded, "the body never landed")
	await step(5)

	var after := _capsule_span(player)
	assert_almost_eq(after.x, standing.x, 0.001,
		"the body was left coiled: capsule floor is %.3f m, standing is %.3f m"
		% [after.x, standing.x])
	assert_almost_eq(after.y, standing.y, 0.001, "the capsule crown was left low")

func test_a_coil_that_lands_does_not_bury_the_body() -> void:
	# THE FAILURE THIS EXISTS FOR. A centre-anchored capsule grown back to
	# standing drops its floor by half the shrink, so a body that touched down
	# still coiled and only then stood up ends the tick with its feet below the
	# floor. See set_capsule_height()'s own warning about the crown-anchored
	# option that was removed for doing this.
	var player: Player = await _jumping()

	# ⚠️ THE COIL IS LENGTHENED HERE ON PURPOSE, and without that this case is
	# a lie that passes. A real coil (0.5 s) and a real jump (0.52 s before the
	# descent crosses enter_to_falling_z_speed) end within a frame of each
	# other, so on flat ground the body is ALWAYS out of the coil before it
	# touches down -- the assertions below would hold while the landing branch
	# they exist for never ran once. The geometry that reaches that branch in
	# play is a ledge at roughly jump height; holding the tuck open is how to
	# reach it in a fixture with no geometry but a floor.
	player.config.coil.duration = 5.0
	var resting_y: float = 0.0
	# The floor's top surface is y = 0 (TestWorld.place()), so a standing body
	# rests with its origin half a capsule above it.
	resting_y = player.standing_height() * 0.5

	_world["input"].press_crouch()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: not coiled")

	# Watched rather than assumed: "it landed and was not buried" is equally
	# true of a body that left the coil a metre up, and that is precisely the
	# reading that made the first version of this test worthless.
	var coiled_near_the_floor := false
	for i in 300:
		await step(1)
		if player.move_manager.current_name == Move.COIL \
				and player.global_position.y < resting_y + 0.3:
			coiled_near_the_floor = true
		if player.grounded:
			break
	assert_true(player.grounded, "the coil never landed")
	assert_true(coiled_near_the_floor,
		"the body was out of the coil before it neared the floor, so the landing branch never ran")
	await step(5)

	assert_almost_eq(player.global_position.y, resting_y, 0.05,
		"landing out of a coil left the body at y %.3f, resting height is %.3f"
		% [player.global_position.y, resting_y])

# --- the risk -------------------------------------------------------------------

func test_a_coil_runs_no_probes() -> void:
	# Anti-corrosion, in the shape docs/feel-backlog.md 44 settled on: the
	# capability matrix is data, and the thing most likely to break it is
	# someone "fixing" a coil that refuses to grab a ledge in reach.
	#
	# ⚠️ THAT REFUSAL IS THE MOVE. ✅ The owner: "在此期间无法触发StepUp或Grab,
	# 所以这个技巧有一定的风险, 判断失误可能就会直接撞到障碍边缘掉下去摔死".
	var cfg := MovementConfig.new()
	assert_false(cfg.coil.check_for_grab, "Coil must not check for a grab")
	assert_false(cfg.coil.check_for_vault_over, "Coil must not check for a vault")
	assert_false(cfg.coil.check_for_wall_climb, "Coil must not check for a wall")

func test_only_jump_offers_a_coil() -> void:
	# The entry lives in MoveConfig.check_for_coil rather than in JumpMove's
	# body, so this is where "which states may coil" is actually readable.
	var cfg := MovementConfig.new()
	assert_true(cfg.jump.check_for_coil, "Jump is the one state that may coil")
	assert_false(cfg.falling.check_for_coil, "Falling may not coil")
	assert_false(cfg.coil.check_for_coil, "a coil may not coil again")

# --- what the tuck is FOR ---------------------------------------------------------

## A slab of geometry whose top surface sits at `top_y`, wide enough that the
## capsule cannot miss it sideways. Freed with the world.
func _slab_at(top_y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.2, 12.0)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	# UNDER THE PLAYER, not at the origin. _jumping() runs forward for 40 ticks
	# before taking off, so by now the body is metres down +/-Z and a slab at
	# the world origin proves nothing -- which is exactly how the first version
	# of this passed against the very regression it was written to catch.
	var at: Vector3 = (_world["player"] as Player).global_position
	body.global_position = Vector3(at.x, top_y - 0.1, at.z)
	_props.append(body)
	return body

func test_a_coil_does_not_end_early_over_geometry_it_is_clearing() -> void:
	# ⚠️ THE REGRESSION THIS EXISTS FOR IS A DESIGN ERROR, NOT A BUG, which is
	# why it is pinned rather than left to a comment.
	#
	# A version of CoilMove watched every tick for "would a standing capsule
	# fit here" and ended the tuck when the answer went false. It passed every
	# other test in this file. ✅ The owner killed it on sight, because that
	# answer is false in precisely the places the move exists for: "它就是用来
	# 通过不蜷缩无法通过的地方，比如越过会受伤的铁丝网...还有个速通技巧就是使用
	# 这个技巧直接精准跳进通风管道，你随手加的检测会让角色无法跳进去". Putting
	# the legs down over razor wire is the worst available outcome, and that
	# check chose it every time.
	#
	# The fixture is that geometry reduced to its essential: a slab threaded
	# BETWEEN the two sets of feet. The tucked capsule clears it, a standing one
	# would not, and nothing here should notice it at all.
	var player: Player = await _jumping()
	player.config.coil.duration = 5.0
	_world["input"].press_crouch()
	# Past boost_duration, so the shrink has finished and the gap between the
	# two sets of feet is at its full size. Still rising at this point -- the
	# jump has ~0.4 s of climb and the shrink takes 0.25 s.
	await step(17)
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: not coiled")
	assert_gt(player.velocity.y, 0.0,
		"test setup: the body must still be rising, or it simply lands on the slab")

	var coiled_feet: float = player.global_position.y - player.current_capsule_height() * 0.5
	var standing_feet: float = player.global_position.y - player.standing_height() * 0.5
	var slab_top: float = (coiled_feet + standing_feet) * 0.5
	assert_lt(standing_feet, slab_top,
		"test setup: the slab does not reach the standing feet, so it proves nothing")
	assert_gt(coiled_feet, slab_top,
		"test setup: the slab blocks the tucked feet too, so it proves nothing")
	_slab_at(slab_top)

	await step(3)
	assert_eq(player.move_manager.current_name, Move.COIL,
		"the coil ended over geometry it was clearing (got %s)"
		% player.move_manager.current_name)

func test_a_coil_lands_into_a_crouch_rather_than_deciding_for_itself() -> void:
	# ✅ THE OWNER'S RULE, and it is the two moves either side of this one:
	# "不能恢复站立，和翻滚和滑铲一样，如果当时无法站立就转蹲下；比如缩腿跳进
	# 通风管道". SkillRollMove and SlideMove both end in CROUCH when the head is
	# blocked, and CrouchMove already knows how to wait for room.
	#
	# 📌 ASKED OF THE MOVE DIRECTLY rather than through a duct-shaped fixture,
	# because that fixture cannot exist on flat ground: clearing a roof low
	# enough to block standing needs more headroom to JUMP through than to
	# stand under. A real duct is a hole in a wall entered horizontally. What is
	# actually under test is the hand-off, and the hand-off is one function.
	var player: Player = await _jumping()
	var coil := player.move_manager.move_for(Move.COIL) as CoilMove
	assert_not_null(coil, "there is no CoilMove to ask")

	# An ordinary landing goes to the crouch, NOT to Walking -- the coil does
	# not get to decide, because at this instant it cannot: its capsule is
	# still centre-anchored, so a standing overlap test reads the ground it is
	# resting on as a blocked head and answers "no room" even under open sky.
	assert_eq(coil.landing_destination(0.5, false), Move.CROUCH,
		"an ordinary landing out of a coil did not hand over to the crouch")
	# The two landings that already own themselves are untouched.
	assert_eq(coil.landing_destination(3.0, true), Move.SKILL_ROLL,
		"a rolled landing was taken away from the roll")
	assert_eq(coil.landing_destination(
		player.config.pawn.hard_landing_height + 1.0, false), Move.LANDING,
		"a hard landing was taken away from the landing lockout")

## A ceiling whose UNDERSIDE sits at `bottom_y`, over the body's own position.
func _roof_at(bottom_y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.2, 12.0)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	var at: Vector3 = (_world["player"] as Player).global_position
	body.global_position = Vector3(at.x, bottom_y + 0.1, at.z)
	_props.append(body)
	return body

func test_a_coil_into_a_duct_stays_crouched() -> void:
	# ✅ THE OWNER, on how a duct is actually entered: "需要滑墙跳后蜷缩进去".
	# A wall-run kick hands off to Jump, and Jump is what offers a coil -- so a
	# tuck can happen high up and travelling horizontally, which is what puts a
	# body through an opening in a WALL. I had claimed this case could not be
	# built on flat ground; that was only true of jumping straight up into it.
	#
	# The wall run itself is not what is under test and is not built here. What
	# the duct actually IS, geometrically, is a stretch where the ceiling is one
	# crouch above the floor -- so the fixture is that, closed around a body
	# that is already tucked and already moving.
	var player: Player = await _jumping()
	player.config.coil.duration = 5.0
	_world["input"].press_crouch()
	await step(17)
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: not coiled")

	# Wait for the descent, so closing a ceiling over the body does not simply
	# stop a climb it was still making.
	for i in 120:
		await step(1)
		if player.velocity.y < 0.0:
			break
	assert_lt(player.velocity.y, 0.0, "test setup: never started descending")
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: left the coil")

	var tucked_feet: float = player.global_position.y - player.current_capsule_height() * 0.5
	var duct_floor: float = tucked_feet - 0.05
	# One crouch of clearance plus a finger's width: a tucked body fits, a
	# crouched one fits, a standing one has no chance.
	var duct_roof: float = duct_floor + player.config.crouch.crouch_capsule_height + 0.1
	assert_lt(duct_roof, duct_floor + player.standing_height(),
		"test setup: the duct is tall enough to stand in, so it proves nothing")
	_slab_at(duct_floor)
	_roof_at(duct_roof)

	for i in 120:
		await step(1)
		if player.grounded:
			break
	assert_true(player.grounded, "never landed on the duct floor")
	# Released, so nothing but the roof is keeping the body down.
	_world["input"].release_crouch()
	await step(15)

	assert_eq(player.move_manager.current_name, Move.CROUCH,
		"a coil that landed inside a duct did not settle into a crouch (got %s)"
		% player.move_manager.current_name)
	assert_lt(player.current_capsule_height(), player.standing_height() - 0.01,
		"the body stood up into the duct roof (capsule is %.2f m)"
		% player.current_capsule_height())

func test_a_coil_that_lands_in_the_open_gets_back_up() -> void:
	# The other half of the hand-off above: passing through Crouch must not
	# LEAVE the player crouched when there is nothing overhead. CrouchMove
	# stands up on its own once the key is released and has_headroom() agrees,
	# so the coil needs no code for this -- which is the point of handing over.
	var player: Player = await _jumping()
	player.config.coil.duration = 5.0
	_world["input"].press_crouch()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.COIL, "test setup: not coiled")

	for i in 300:
		await step(1)
		if player.grounded:
			break
	assert_true(player.grounded, "the coil never landed")
	# Released only now: held through the landing, staying crouched is correct.
	_world["input"].release_crouch()
	await step(10)

	assert_eq(player.move_manager.current_name, Move.WALKING,
		"a coil landing under open sky did not get back up (got %s)"
		% player.move_manager.current_name)
	assert_almost_eq(player.current_capsule_height(), player.standing_height(), 0.001,
		"the body is still compressed at %.2f m" % player.current_capsule_height())
