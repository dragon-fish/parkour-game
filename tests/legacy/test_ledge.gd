extends ParkourTest

# Trigger a jump on a run-up that has actually reached (most of) ground speed,
# not merely "faster than a walk" -- with air control now barely able to
# change anything (see air_accel's own comment in movement_config.gd), the
# speed at the MOMENT of takeoff is what determines the whole arc, so a jump
# fired too early lands short in a way a fast, weak-air-control jump cannot
# correct for. Every _jump_at_ledge* caller below presses jump on this same
# gate rather than each hand-rolling its own threshold.
const JUMP_TRIGGER_RATIO := 0.9

func _jump_at_ledge(block_height: float) -> Dictionary:
	return await _jump_at_ledge_with(block_height, 4.0, MovementConfig.new())

## `depth` is the block's z extent; 4.0 is the original geometry. Callers that
## need a SHALLOW platform (one the mantle can overshoot) pass their own, and
## `cfg` lets them exercise a non-default MovementConfig without duplicating the
## whole setup -- the same shape tests/test_vault.gd's _running_at_obstacle uses.
func _jump_at_ledge_with(block_height: float, depth: float, cfg: MovementConfig) -> Dictionary:
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

	# Placed near the FAR end of a full jump's reach, not partway through it.
	# ledge_query()'s height gate only opens in a narrow window near the
	# BOTTOM of the arc (mirrors the reasoning behind VaultArea's own
	# LEDGE_RUNUP_MARGIN in tools/arena_builder.gd) -- a block placed mid-arc
	# leaves the player still rising, or at apex, too high above the block's
	# top to ever register as a grab under the new floaty jump. Closed-form
	# projectile arithmetic on the run-up speed (the ground speed cap, same
	# formula as MovementConfig.gravity's own comment), with a margin under
	# the theoretical ceiling since the run-up here starts from a dead stop,
	# not already at speed.
	var jump_airtime: float = 2.0 * cfg.jump_velocity / maxf(cfg.gravity, 0.001)
	var max_jump_distance: float = cfg.ground_speed * jump_airtime
	# The margin places the NEAR FACE, not the block's centre: ledge_query()'s
	# forward probe and its height gate both care about where the FACE is, not
	# where the block's z-centre happens to sit, so measuring from the centre
	# would silently shift the actual approach distance by depth/2 every time
	# a caller passes a different depth.
	#
	# The margin itself, measured directly rather than derived, differs by
	# platform depth, and that split is load-bearing, not incidental:
	#   - depth >= 1.0 (the normal 4.0 m platform every hang/mantle test
	#     uses): 0.95 is the closest margin that grabs at all (anything lower
	#     flies over every time, matching arena_builder.gd's own
	#     LEDGE_RUNUP_MARGIN reasoning), but 0.95-1.2 all grab at the SAME
	#     height, high enough up the block's face that the fall to the floor
	#     afterward takes longer than ledge_regrab_cooldown (0.45 s) --
	#     test_dropping_off_a_ledge_does_not_instantly_regrab_it catches this
	#     directly: cooldown expires mid-fall, still inside the grab height
	#     window, and the ledge gets grabbed a second time. 1.3 is the first
	#     margin where the grab happens late enough in the arc (closer to the
	#     ground) that the remaining fall clears inside the cooldown.
	#   - depth < 1.0 (the shallow 0.6 m platform test_a_mantle_that_finds_no_
	#     floor_arms_the_regrab_cooldown uses, specifically so the mantle
	#     overshoots it): 1.3 no longer grabs at all -- a shallower platform's
	#     top face is a much smaller target for the same forward+down probe
	#     pair, and by 1.25-1.3 it is missed outright. 1.1 sits in the middle
	#     of the range (1.0-1.2) that reliably grabs a platform this shallow.
	# Neither figure is a closed-form quantity -- ledge_query()'s exact height
	# at grab time is a property of its own probe geometry, not something this
	# generator can derive -- so both are pinned to what was actually measured
	# against the live states, against the specific tests each one guards.
	var block_distance_margin: float = 1.3 if depth >= 1.0 else 1.1
	var near_face_z: float = -max_jump_distance * block_distance_margin
	var block_z: float = near_face_z - depth * 0.5

	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, block_height, depth)
	shape.shape = box
	block.add_child(shape)
	get_tree().root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, block_height * 0.5, block_z)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	# No sprint key: forward input alone already reaches ground_speed.
	world["block"] = block
	world["block_top"] = block_height
	# The player runs toward -Z, so the face it climbs is the block's +Z one.
	world["block_near_face_z"] = block_z + depth * 0.5
	world["block_far_face_z"] = block_z - depth * 0.5
	return world

func test_reaching_a_ledge_grabs_it() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]

	var grabbed := false
	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			grabbed = true
			break
	assert_true(grabbed, "jumping at a head-height ledge should grab it")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## NOTE: this is close to tautological -- the hang branch never calls
## move_and_slide() and never touches position, so nothing in it CAN move the
## body regardless of what this asserts; there is no gravity application left
## to disable to make it fail "for the wrong reason" the way a real drift bug
## would. What it still guards is real, though: a REGRESSION that starts
## applying gravity while hanging (the way AirState does) would move the
## body, and this is what would catch it. Renamed from
## test_hanging_holds_position to name that directly.
func test_hanging_applies_no_gravity() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2.ZERO
	var held := player.global_position
	await step(20)
	assert_true(player.global_position.distance_to(held) < 0.05, \
		"a hanging player must not fall under gravity or otherwise drift")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## "Mantled onto the ledge" is a claim about where the player ENDS UP, not
## about how high the scripted arc got. The previous version of this test
## asserted `y > 2.0` on the hand-off tick -- but the lerp target is
## `edge.y + standing_height/2` BY CONSTRUCTION, so that reading is high the
## instant the arc finishes no matter where horizontally it put the body. It
## could not fail for any horizontal-placement defect, which is exactly how the
## inverted mantle_forward_offset sign survived: the landing sat in FRONT of
## the wall face, the body was briefly "high" over open air, and this passed.
##
## So it now does what test_a_vault_clears_the_obstacles_far_face does: let the
## hand-off settle for ~30 ticks under GroundState's own move_and_slide(), and
## only then ask whether the player is standing on the platform -- still Ground,
## grounded, above the block's top, AND horizontally inside the block's
## footprint.
##
## That last one is doing real work, and "still Ground and grounded" alone is
## not enough without it. Measured against this exact geometry with the sign
## restored to the buggy `-=`: the landing sits 0.24 m in FRONT of the face, the
## body drops for four ticks, and then the capsule's bottom sphere catches the
## block's top EDGE and is reported grounded -- perched on the lip at y = 3.40,
## outside the platform, which satisfies Ground, grounded and "y above the block
## top" all three. Only asking where it is HORIZONTALLY separates standing on
## the platform from balancing on its corner.
func test_pressing_forward_mantles_onto_the_ledge() -> void:
	await step(1)
	var block_height := 2.6
	var world := await _jump_at_ledge(block_height)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2(0.0, 1.0)
	var handed_off := false
	for i in 200:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			handed_off = true
			break
	assert_true(handed_off, "the mantle never handed off to Ground")

	# Drop the input before the settle window. The block is only 4 m deep, so
	# holding forward for another half second would simply run the player off
	# its FAR edge -- a fall this test would then wrongly report as a failed
	# mantle. Standing still is the honest question here: does the ground the
	# mantle put the player on hold them up?
	world["input"].state.move = Vector2.ZERO
	await step(30)

	assert_true(player.state_machine.current_name == &"Ground", \
		"half a second after the mantle the player is in %s, not standing on the ledge -- the landing point found no floor" \
		% player.state_machine.current_name)
	assert_true(player.grounded, \
		"the player is not grounded half a second after the mantle -- the landing point found no floor")
	assert_gt(player.global_position.y, block_height, \
		"the player ended up below the block top (%f), so the mantle did not leave them on the platform" \
		% block_height)

	var near_face_z: float = world["block_near_face_z"]
	assert_true(player.global_position.z < near_face_z, \
		"the player is at z=%f, still outside the platform's near face (z=%f) -- the mantle left them balanced on the lip rather than standing on the ledge" \
		% [player.global_position.z, near_face_z])

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## LedgeHangState freezes _exit_direction at COMMITMENT -- the tick forward or
## jump is pressed and begin() is called -- not at grab time, specifically so
## that spinning the mouse DURING the 0.42 s scripted climb cannot aim either
## the landing point or the exit shove off the ledge actually grabbed.
## CameraRig.apply_look() keeps turning the body's yaw every physics tick
## regardless of state, so nothing else stops it. The decisive assertion is on
## the HAND-OFF velocity's direction rather than the final resting position:
## the scripted move's landing point (`top`) is computed once, at
## commitment -- before this test ever rotates the player -- so it is
## identical whether or not the mid-climb-sampling bug is present; only the
## direction of the push handed to GroundState at completion actually exposes
## it. Movement input is dropped during the turn so GroundState's own
## acceleration (which would otherwise chase the NEW, rotated wish_dir
## regardless of the bug) cannot mask a wrongly-aimed hand-off.
##
## Complements test_turning_while_hanging_changes_where_the_mantle_lands
## below, which exercises the OTHER capture-moment mistake: sampling facing
## too early (at grab, before commitment) instead of too late.
func test_rotating_mid_climb_still_lands_on_the_grabbed_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	# The direction the mantle actually commits to -- no rotation has
	# happened yet, so this equals whatever _exit_direction is about to be
	# set to the instant forward is pressed below.
	var committed_forward: Vector3 = -player.global_transform.basis.z

	world["input"].state.move = Vector2(0.0, 1.0)
	await step(1)
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: mantle should have started")

	# Whip the view around hard, mid-climb -- AFTER commitment.
	world["input"].state.look = Vector2(-1000.0, 0.0)
	world["input"].state.move = Vector2.ZERO
	await step(1)
	world["input"].state.look = Vector2.ZERO

	var new_forward: Vector3 = -player.global_transform.basis.z
	assert_true(new_forward.dot(committed_forward) < 0.7, \
		"precondition: the mid-climb turn should actually have rotated the player substantially")

	var exit_velocity := Vector3.ZERO
	for i in 200:
		await step(1)
		if player.state_machine.current_name != &"Ledge":
			exit_velocity = player.velocity
			break
	assert_true(player.state_machine.current_name == &"Ground", \
		"mantling should end on the ledge top even after a mid-climb turn")
	assert_gt(player.global_position.y, 2.0, "the player should still be above the ledge")

	var exit_dir := Vector3(exit_velocity.x, 0.0, exit_velocity.z)
	assert_gt(exit_dir.length(), 0.01, \
		"precondition: the mantle should hand off with a horizontal exit speed to have a direction to check")
	assert_gt(exit_dir.normalized().dot(committed_forward), 0.9, \
		"a mid-climb turn aimed the mantle's exit push off the ledge just climbed, instead of the direction actually committed to")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## The OTHER capture-moment mistake: sampling facing too EARLY (at grab, in
## enter()) instead of at commitment. A player is free to hang and turn
## before ever pressing forward -- that is a deliberate choice, not
## interference -- so the climb must follow the facing at the moment it is
## actually committed to, not whatever the grab-time probe rays happened to
## be pointing along. Captures the edge BEFORE turning (turning would re-aim
## the probe rays and could read a different, or no, edge at all -- this
## test is about the DIRECTION capture bug, not about re-probing), and checks
## both the hand-off velocity AND the actual landing position against the
## POST-turn facing.
func test_turning_while_hanging_changes_where_the_mantle_lands() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	var edge_query: Dictionary = player.probes.ledge_query()
	assert_true(edge_query["valid"], "precondition: the grabbed edge should still be probeable from the hang position")
	var edge_point: Vector3 = edge_query["edge"]
	var hang_position: Vector3 = player.global_position

	# Turn substantially WHILE HANGING, before ever pressing forward. Nothing
	# has been committed to yet, so this is simply the player looking around.
	world["input"].state.look = Vector2(-1000.0, 0.0)
	await step(1)
	world["input"].state.look = Vector2.ZERO
	assert_true(player.state_machine.current_name == &"Ledge", \
		"precondition: turning while hanging must not itself end the hang")

	var post_turn_forward: Vector3 = -player.global_transform.basis.z
	assert_true(post_turn_forward.dot(Vector3(0.0, 0.0, -1.0)) < 0.7, \
		"precondition: the hang-turn should actually have rotated the player substantially")

	# NOW commit to the climb, facing the NEW direction.
	world["input"].state.move = Vector2(0.0, 1.0)
	var exit_velocity := Vector3.ZERO
	for i in 90:
		await step(1)
		if player.state_machine.current_name != &"Ledge":
			exit_velocity = player.velocity
			break
	assert_true(player.state_machine.current_name == &"Ground", \
		"mantling should still complete after turning while hanging")

	var exit_dir := Vector3(exit_velocity.x, 0.0, exit_velocity.z)
	assert_gt(exit_dir.length(), 0.01, \
		"precondition: the mantle should hand off with a horizontal exit speed to have a direction to check")
	assert_gt(exit_dir.normalized().dot(post_turn_forward), 0.9, \
		"a turn made while hanging (before committing to the climb) was ignored -- the mantle exited along stale grab-time facing instead of the direction actually faced at commitment")

	# OUTCOME, not formula. The version of this assertion that shipped with the
	# feature recomputed the production expression verbatim
	# (`edge + up - forward * mantle_forward_offset`) and compared the body
	# against it -- which is a mirror, not a test: it agreed with the code
	# whichever SIGN the code used, and so watched the inverted-offset bug go
	# past. Both claims below are about where the body actually ended up,
	# derived from the geometry rather than from the implementation:
	#
	#   1. the climb travelled the way the player was facing at COMMITMENT (the
	#      capture-moment claim this test exists for), and
	#   2. it finished PAST the lip it probed, measured along that same
	#      direction -- not short of it. Landing short is not a near-miss, it is
	#      the body standing over open air in front of the wall, and it is the
	#      only outcome the two possible signs disagree about.
	# Measured from the LIP the state actually probed, not from the hang
	# position: the body necessarily travels from where it hung to the lip as
	# well, and that leg is aimed along the GRAB-time facing (the lip was probed
	# before the turn), so a displacement measured from the hang position is
	# dominated by it and says nothing about either claim.
	var past_lip := Vector3(player.global_position.x - edge_point.x, 0.0, \
		player.global_position.z - edge_point.z)
	assert_gt(past_lip.length(), 0.01, \
		"precondition: the landing should be horizontally displaced from the lip at all")
	# Which SIDE of the lip the body finished on, expressed as a direction
	# rather than as a recomputed landing point. The two possible signs of
	# mantle_forward_offset put the body on opposite sides of the ledge face
	# (dot near +1 versus near -1), and only one of them is standing room --
	# the other leaves the feet at platform height over open air in front of
	# the wall. This also carries the capture-moment claim for the LANDING (as
	# distinct from the exit push checked above): the side it lands on is the
	# side the player faced at commitment, not at grab.
	assert_gt(past_lip.normalized().dot(post_turn_forward), 0.9, \
		"the mantle finished on the %s side of the probed lip; expected it PAST the lip along the committed direction %s, which is where the platform is -- landing on the other side puts the body over open air in front of the face" \
		% [past_lip.normalized(), post_turn_forward])

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## Sanity check for removing the hang's vertical repositioning (see
## enter()'s comment): a grab near the TOP of [ledge_min_height,
## ledge_max_height] now leaves the body hanging well below the standard drop
## instead of being pulled up to it, so the mantle has FARTHER to climb in
## the same fixed mantle_duration. ScriptedMove.advance() is a fixed-TIME
## lerp (elapsed / duration), never a fixed-SPEED one, so this must not
## matter -- confirms it does not by hand-placing a grab at height ~2.75 m
## (just under the 2.8 m default max) and checking the mantle still reaches
## the top within mantle_duration.
func test_mantling_completes_from_the_top_of_the_grab_range() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	# A tall block: its own height above the FLOOR is irrelevant to
	# ledge_query()'s "height" reading, which is measured against the
	# player's own feet at query time -- what matters here is placing the
	# player's feet far below the block's top edge.
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 4.0)
	shape.shape = box
	block.add_child(shape)
	get_tree().root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, 3.0, -6.0)
	await step(1)

	# Feet at world y = 6.0 (edge) - 2.75 = 3.25, well clear of the floor;
	# within ledge_reach (1.0 m default) of the block's near face (z = -4.0).
	player.global_position = Vector3(0.0, 3.25 + player.standing_height() * 0.5, -3.5)
	await step(1)

	var query: Dictionary = player.probes.ledge_query()
	assert_true(query["valid"], "precondition: this hand-placed position should read as a valid ledge grab")
	var height_at_grab: float = query["edge"].y - (player.global_position.y - player.standing_height() * 0.5)
	assert_true(height_at_grab > cfg.ledge_max_height - 0.2, \
		"precondition: this test needs a grab near the TOP of the reachable range, got height %f" % height_at_grab)

	player.state_machine.start(PlayerState.LEDGE)
	await step(1)
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 90:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	assert_true(player.state_machine.current_name == &"Ground", \
		"a grab near the top of the reachable range should still mantle to completion within mantle_duration")
	assert_gt(player.global_position.y, query["edge"].y, \
		"the player should have ended up above the ledge even starting from full stretch")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

## The oscillation the re-grab cooldown exists to prevent, observed directly on
## the path that can actually close the loop: crouch off a ledge and the wall is
## still right in front of you, at the same height, with AirState's ledge_query
## gate the only thing between the drop and an instant re-grab. Without a
## cooldown that gate is open on the very next tick and the player strobes
## Ledge -> Air -> Ledge for as long as crouch is held.
##
## Counted over a window rather than sampled once: "it re-grabbed" is not a
## thing a single reading of current_name can see, since the strobe spends every
## other tick in each state.
func test_dropping_off_a_ledge_does_not_instantly_regrab_it() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]

	var grabs := [0]
	player.state_machine.state_changed.connect(func(_from: StringName, to: StringName) -> void:
		if to == &"Ledge":
			grabs[0] += 1)

	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")
	assert_true(grabs[0] == 1, "precondition: exactly one grab so far, saw %d" % grabs[0])

	world["input"].state.move = Vector2.ZERO
	world["input"].state.crouch_held = true
	await step(60)

	assert_true(grabs[0] == 1, \
		"the player re-grabbed the ledge it had just dropped off %d time(s) -- crouch-dropping must arm the re-grab cooldown, or the drop oscillates against the same wall" \
		% (grabs[0] - 1))
	assert_true(player.state_machine.current_name != &"Ledge", \
		"a second after crouching off the ledge the player is hanging from it again")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## The other half of the same hole, and the half that was actually open: a
## mantle that COMPLETES used to leave the cooldown at zero, because
## start_ledge_cooldown() was called on the crouch-drop path only. Any mantle
## whose landing point turns out not to be standing room then drops to Air with
## nothing at all gating the next ledge_query() -- the same oscillation as
## above, but reached through the state's headline action instead of its exit
## hatch, and on geometry the player cannot see is different.
##
## The geometry here is the reviewer's case made unambiguous: a platform
## shallower than mantle_forward_offset + the capsule radius, so the landing
## overshoots its far face entirely and hangs over open air. Rather than shave
## the platform down to a few centimetres (where whether the capsule catches the
## far lip comes down to float noise), mantle_forward_offset is raised on a
## test-local config -- the shipped default is untouched, and the relationship
## being exercised is the same one.
func test_a_mantle_that_finds_no_floor_arms_the_regrab_cooldown() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	# 1.2 + capsule radius 0.4 = 1.6, comfortably more than the 0.6 m platform.
	cfg.mantle_forward_offset = 1.2
	var world := await _jump_at_ledge_with(2.6, 0.6, cfg)
	var player: Player = world["player"]

	var grabs := [0]
	player.state_machine.state_changed.connect(func(_from: StringName, to: StringName) -> void:
		if to == &"Ledge":
			grabs[0] += 1)

	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	assert_true(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
		if player.state_machine.current_name != &"Ledge":
			break
	assert_true(player.state_machine.current_name != &"Ledge", "precondition: the mantle should have handed off")

	# Precondition, and the whole point of the geometry: this landing really
	# does find no floor. Without it the assertion below would be checking the
	# cooldown on a mantle that never needed one.
	var went_airborne := false
	var could_grab_while_airborne := false
	for i in 10:
		await step(1)
		if player.state_machine.current_name == &"Air":
			went_airborne = true
			could_grab_while_airborne = player.can_grab_ledge()
			break
	assert_true(went_airborne, \
		"precondition: the mantle onto a platform shallower than mantle_forward_offset should leave the player airborne")
	assert_true(not could_grab_while_airborne, \
		"the mantle handed off without arming the re-grab cooldown, so AirState's ledge gate was open on the very tick the landing failed -- that is the unbounded climb/fall/re-climb loop")

	# ...and it stays shut for about as long as the config says.
	await step(int(cfg.ledge_regrab_cooldown * 60.0) - 6)
	assert_true(not player.can_grab_ledge(), \
		"the cooldown expired well before ledge_regrab_cooldown (%f s) had elapsed" % cfg.ledge_regrab_cooldown)

	assert_true(grabs[0] == 1, \
		"the ledge was grabbed %d times during a single approach -- the mantle is oscillating against it" % grabs[0])

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_crouching_releases_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > player.config.ground_speed * JUMP_TRIGGER_RATIO and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2.ZERO
	world["input"].state.crouch_held = true
	await step(5)
	assert_true(player.state_machine.current_name == &"Air", "crouching should drop off the ledge")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)
