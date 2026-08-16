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

## LedgeHangState freezes the direction the mantle pushes and exits along at
## grab time (_exit_direction), specifically so that spinning the mouse while
## climbing cannot aim either the landing point or the exit shove off the
## ledge actually grabbed -- CameraRig.apply_look() keeps turning the body's
## yaw every physics tick regardless of state, so nothing else stops it. The
## decisive assertion is on the HAND-OFF velocity's direction rather than the
## final resting position: the scripted move's landing point (`top`) is
## computed once, at climb-start, before this test ever rotates the player,
## so it is identical whether or not the exit-velocity bug is present -- only
## the direction of the push handed to GroundState at completion actually
## exposes it. Movement input is dropped during the turn so GroundState's own
## acceleration (which would otherwise chase the NEW, rotated wish_dir
## regardless of the bug) cannot mask a wrongly-aimed hand-off.
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

	# The direction the mantle actually commits to.
	var committed_forward: Vector3 = -player.global_transform.basis.z

	world["input"].state.move = Vector2(0.0, 1.0)
	await step(1)
	check(player.state_machine.current_name == &"Ledge", "precondition: mantle should have started")

	# Whip the view around hard, mid-climb.
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
		"a mid-climb turn aimed the mantle's exit push off the ledge just climbed, instead of the direction actually grabbed")

	world["block"].queue_free()
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
