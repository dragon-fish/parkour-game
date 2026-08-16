extends TestCase

func _jump_at_ledge(block_height: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, block_height, 4.0)
	shape.shape = box
	block.add_child(shape)
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, block_height * 0.5, -6.0)
	await step(1)

	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.sprint_held = true
	world["block"] = block
	return world

func test_reaching_a_ledge_grabs_it() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]

	var grabbed := false
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			grabbed = true
			break
	check(grabbed, "jumping at a head-height ledge should grab it")

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
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	check(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2.ZERO
	var held := player.global_position
	await step(20)
	check(player.global_position.distance_to(held) < 0.05, \
		"a hanging player must not fall under gravity or otherwise drift")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_pressing_forward_mantles_onto_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", "mantling should end on the ledge top")
	check_greater(player.global_position.y, 2.0, "the player should now be above the ledge")

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
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	check(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	# The direction the mantle actually commits to -- no rotation has
	# happened yet, so this equals whatever _exit_direction is about to be
	# set to the instant forward is pressed below.
	var committed_forward: Vector3 = -player.global_transform.basis.z

	world["input"].state.move = Vector2(0.0, 1.0)
	await step(1)
	check(player.state_machine.current_name == &"Ledge", "precondition: mantle should have started")

	# Whip the view around hard, mid-climb -- AFTER commitment.
	world["input"].state.look = Vector2(-1000.0, 0.0)
	world["input"].state.move = Vector2.ZERO
	await step(1)
	world["input"].state.look = Vector2.ZERO

	var new_forward: Vector3 = -player.global_transform.basis.z
	check(new_forward.dot(committed_forward) < 0.7, \
		"precondition: the mid-climb turn should actually have rotated the player substantially")

	var exit_velocity := Vector3.ZERO
	for i in 200:
		await step(1)
		if player.state_machine.current_name != &"Ledge":
			exit_velocity = player.velocity
			break
	check(player.state_machine.current_name == &"Ground", \
		"mantling should end on the ledge top even after a mid-climb turn")
	check_greater(player.global_position.y, 2.0, "the player should still be above the ledge")

	var exit_dir := Vector3(exit_velocity.x, 0.0, exit_velocity.z)
	check_greater(exit_dir.length(), 0.01, \
		"precondition: the mantle should hand off with a horizontal exit speed to have a direction to check")
	check_greater(exit_dir.normalized().dot(committed_forward), 0.9, \
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
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break
	check(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	var edge_query: Dictionary = player.probes.ledge_query()
	check(edge_query["valid"], "precondition: the grabbed edge should still be probeable from the hang position")
	var edge_point: Vector3 = edge_query["edge"]

	# Turn substantially WHILE HANGING, before ever pressing forward. Nothing
	# has been committed to yet, so this is simply the player looking around.
	world["input"].state.look = Vector2(-1000.0, 0.0)
	await step(1)
	world["input"].state.look = Vector2.ZERO
	check(player.state_machine.current_name == &"Ledge", \
		"precondition: turning while hanging must not itself end the hang")

	var post_turn_forward: Vector3 = -player.global_transform.basis.z
	check(post_turn_forward.dot(Vector3(0.0, 0.0, -1.0)) < 0.7, \
		"precondition: the hang-turn should actually have rotated the player substantially")

	# NOW commit to the climb, facing the NEW direction.
	world["input"].state.move = Vector2(0.0, 1.0)
	var exit_velocity := Vector3.ZERO
	for i in 90:
		await step(1)
		if player.state_machine.current_name != &"Ledge":
			exit_velocity = player.velocity
			break
	check(player.state_machine.current_name == &"Ground", \
		"mantling should still complete after turning while hanging")

	var exit_dir := Vector3(exit_velocity.x, 0.0, exit_velocity.z)
	check_greater(exit_dir.length(), 0.01, \
		"precondition: the mantle should hand off with a horizontal exit speed to have a direction to check")
	check_greater(exit_dir.normalized().dot(post_turn_forward), 0.9, \
		"a turn made while hanging (before committing to the climb) was ignored -- the mantle exited along stale grab-time facing instead of the direction actually faced at commitment")

	var expected_top: Vector3 = edge_point + Vector3(0.0, player.standing_height() * 0.5, 0.0) \
		- post_turn_forward * player.config.mantle_forward_offset
	check(player.global_position.distance_to(expected_top) < 0.1, \
		"the mantle landed at %s, expected %s near the post-turn facing -- grab-time facing was used instead of the facing at commitment" \
		% [player.global_position, expected_top])

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
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
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
	tree.root.add_child(block)
	await step(1)
	block.global_position = Vector3(0.0, 3.0, -6.0)
	await step(1)

	# Feet at world y = 6.0 (edge) - 2.75 = 3.25, well clear of the floor;
	# within ledge_reach (1.0 m default) of the block's near face (z = -4.0).
	player.global_position = Vector3(0.0, 3.25 + player.standing_height() * 0.5, -3.5)
	await step(1)

	var query: Dictionary = player.probes.ledge_query()
	check(query["valid"], "precondition: this hand-placed position should read as a valid ledge grab")
	var height_at_grab: float = query["edge"].y - (player.global_position.y - player.standing_height() * 0.5)
	check(height_at_grab > cfg.ledge_max_height - 0.2, \
		"precondition: this test needs a grab near the TOP of the reachable range, got height %f" % height_at_grab)

	player.state_machine.start(PlayerState.LEDGE)
	await step(1)
	check(player.state_machine.current_name == &"Ledge", "precondition: should be hanging")

	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 90:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", \
		"a grab near the top of the reachable range should still mantle to completion within mantle_duration")
	check_greater(player.global_position.y, query["edge"].y, \
		"the player should have ended up above the ledge even starting from full stretch")

	block.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_crouching_releases_the_ledge() -> void:
	await step(1)
	var world := await _jump_at_ledge(2.6)
	var player: Player = world["player"]
	for i in 400:
		await step(1)
		if player.horizontal_speed() > 5.0 and player.is_on_floor():
			world["input"].press_jump()
		if player.state_machine.current_name == &"Ledge":
			break

	world["input"].state.move = Vector2.ZERO
	world["input"].state.crouch_held = true
	await step(5)
	check(player.state_machine.current_name == &"Air", "crouching should drop off the ledge")

	world["block"].queue_free()
	TestWorld.teardown(world)
	await step(1)
