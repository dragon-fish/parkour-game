extends ParkourTest

# STRUCTURAL: which shapes are a spring board and which are not, and what the
# move does with one. The numbers themselves (9.5, 0.64, 1.12, 53) are the
# original's and are not asserted here beyond "the move uses the config's".

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _props: Array[Node] = []

func after_each() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

## A standing player on the fixture floor (top at y = 0), facing -Z.
func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: not standing")
	return player

## A pole `height` tall standing on the floor, its top centred at (x, z).
## 0.3 m across by default: thinner than the capsule, which is the case a ray
## misses. `depth` (along Z) defaults to `across`.
##
## POSITIONED BEFORE IT ENTERS THE TREE. Added first and moved after, the box
## spends one physics tick at the world origin, which is inside the player's
## capsule: move_and_slide depenetrates the body 0.49 m sideways and drops it
## into Falling, and every probe fired afterwards walks a line the props are
## not on.
func _pole(x: float, z: float, height: float, across: float = 0.3, depth: float = -1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(across, height, depth if depth > 0.0 else across)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(x, height * 0.5, z)
	get_tree().root.add_child(body)
	_props.append(body)
	return body

## The two poles of a spring board ahead of a player at the origin facing -Z:
## the first `ahead` metres out, the second 1.12 m further, turned `bearing_deg`
## off the facing about the first.
func _spring_board_ahead(ahead: float, bearing_deg: float = 0.0) -> void:
	var cfg := SpringBoardConfig.new()
	_pole(0.0, -ahead, cfg.plant_1_height)
	var second := Vector3(0.0, 0.0, -cfg.plant_spacing).rotated(Vector3.UP, deg_to_rad(bearing_deg))
	_pole(second.x, -ahead + second.z, cfg.plant_1_height + 0.6)

func test_two_plants_ahead_are_a_spring_board() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0)
	await step(2)
	var hit: Dictionary = player.probes.springboard_query()
	assert_true(hit["valid"], "two plants ahead were not seen as a spring board")
	assert_almost_eq(hit["plant_1"].y, 0.64, 0.05, "the first plant's top is wrong")
	assert_almost_eq(hit["plant_2"].y, 1.24, 0.05, "the second plant's top is wrong")
	assert_almost_eq(hit["plant_2"].z, -2.12, 0.35, "the second plant is not where the pole is")

func test_one_plant_is_not_a_spring_board() -> void:
	var player: Player = await _standing_player()
	_pole(0.0, -1.0, 0.64)
	await step(2)
	assert_false(player.probes.springboard_query()["valid"],
		"a single low pole was taken for a spring board")

func test_the_second_plant_must_lie_inside_the_approach_fan() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0, 90.0)
	await step(2)
	assert_false(player.probes.springboard_query()["valid"],
		"a second plant square to the side of the facing was accepted")

func test_the_second_plant_may_lie_off_the_facing_inside_the_fan() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0, 40.0)
	await step(2)
	assert_true(player.probes.springboard_query()["valid"],
		"a second plant 40 degrees off the facing was refused")

func test_a_first_plant_beyond_the_trigger_distance_is_out_of_reach() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(2.0)
	await step(2)
	assert_false(player.probes.springboard_query()["valid"],
		"a spring board 2 m out was accepted")

func test_a_wide_step_is_a_spring_board_too() -> void:
	# The plants are points on whatever is there: two tiers 3 m wide work
	# exactly like two poles. Each a metre deep, so the second tier's face
	# sits plant_spacing from the first plant (the first tier's front edge),
	# the way the recording's two crates did.
	var player: Player = await _standing_player()
	_pole(0.0, -1.5, 0.64, 3.0, 1.0)
	_pole(0.0, -2.62, 1.24, 3.0, 1.0)
	await step(2)
	assert_true(player.probes.springboard_query()["valid"],
		"two wide tiers were not seen as a spring board")

## AN EDGE GRAZE IS NOT A FOOTING. The forward samples are anchored to the
## FEET, so where the player happens to stop decides the grid's phase against
## a plant's face. A sample landing short of that face still catches the top
## EDGE with the probe sphere, and the point it returns hangs off the side:
## the query says valid, fits_standing_at refuses it, and WalkingMove drops
## the whole thing to a plain jump. Measured before springboard_query()
## stepped off the lip, the refusal alternated with the player's position at a
## quarter of plant_sample_step -- half of all approaches lost the move.
##
## Swept over a full cycle of the grid, and including the case that matters
## most: the capsule walked into the first plant's face and stopped a radius
## short of it, which is where a player who runs at a spring board ends up.
func test_every_approach_position_finds_plants_the_body_can_stand_on() -> void:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0)
	await step(2)
	var home: Vector3 = player.global_position
	# Facing -Z, so +Z backs away: a quarter of plant_sample_step each time
	# covers one full phase, and -0.45 is the capsule against the face
	# (the first plant's front is at z = -0.85).
	for offset in [0.0, 0.025, 0.05, 0.075, -0.45]:
		player.global_position = Vector3(home.x, home.y, offset)
		player.velocity = Vector3.ZERO
		await step(2)
		var hit: Dictionary = player.probes.springboard_query()
		assert_true(hit["valid"],
			"no spring board seen from z = %.3f" % offset)
		if not hit["valid"]:
			continue
		assert_true(player.fits_standing_at(hit["plant_1"]),
			"from z = %.3f the first plant %s is not standable" % [offset, hit["plant_1"]])
		assert_true(player.fits_standing_at(hit["plant_2"]),
			"from z = %.3f the second plant %s is not standable" % [offset, hit["plant_2"]])

# --- the move --------------------------------------------------------------

## Stands the player 1 m short of a spring board and presses jump.
func _press_jump_at_a_spring_board(bearing_deg: float = 0.0) -> Player:
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0, bearing_deg)
	await step(2)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(1)
	_world["input"].state.jump_pressed = false
	return player

func test_jump_at_a_spring_board_is_a_spring_board_not_a_jump() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	assert_eq(player.move_manager.current_name, Move.SPRING_BOARD,
		"jump in front of two plants did not spring board")

func test_jump_with_only_one_plant_ahead_is_a_plain_jump() -> void:
	var player: Player = await _standing_player()
	_pole(0.0, -1.0, 0.64)
	await step(2)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"one pole ahead turned a jump into something else")

func test_a_plant_the_body_cannot_stand_on_is_refused() -> void:
	# A slab hanging 1.0 m above the second plant's top: the capsule is 1.8 m.
	var player: Player = await _standing_player()
	_spring_board_ahead(1.0)
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.2, 1.0)
	shape.shape = box
	roof.add_child(shape)
	get_tree().root.add_child(roof)
	roof.global_position = Vector3(0.0, 1.24 + 1.0 + 0.1, -2.12)
	_props.append(roof)
	await step(2)
	_world["input"].state.jump_pressed = true
	_world["input"].state.jump_held = true
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"a spring board the body cannot stand on top of was still taken")

func test_the_steps_put_the_feet_on_each_plant_in_turn() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	# HELD FROM BEFORE THE CLIMB AND NEVER LET GO, which is the real case: a
	# player runs at the board with W down. Neither the walk-up nor the steps
	# read input.move, so the arcs below must land on the plants to the
	# centimetre with the key still down -- that, not a lock, is what makes
	# movement input harmless here. A lock would take the mouse with it, and
	# the view has to stay live for the throw to be aimable.
	_world["input"].state.move = Vector2(0.0, 1.0)  # W
	# Walk on to the first plant's face.
	var ticks: int = 0
	while not board.is_stepping() and ticks < 60:
		await step(1)
		ticks += 1
	assert_true(board.is_stepping(), "the steps never began")
	assert_true(player.grounded, "stepping on the plants is not declared grounded")
	await step(int(player.config.spring_board.step_time_1 * 60.0))
	var feet_1: float = player.probes.feet_y()
	assert_almost_eq(feet_1, 0.64, 0.08,
		"after the first step the feet are at %.2f, not on the first plant" % feet_1)
	await step(int(player.config.spring_board.step_time_2 * 60.0))
	var feet_2: float = player.probes.feet_y()
	assert_almost_eq(feet_2, 1.24, 0.08,
		"after the second step the feet are at %.2f, not on the second plant" % feet_2)

func test_the_throw_is_the_configs_and_the_rise_ends_in_falling() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	var cfg: SpringBoardConfig = player.config.spring_board
	var ticks: int = 0
	# Bounded IN THE CONDITION, like every other loop here: a GUT assert does
	# not stop execution, so a throw that never comes spins this test forever
	# instead of failing it -- which is a hung suite, not a red one.
	while (board.is_stepping() or not board.has_launched()) and ticks < 120:
		await step(1)
		ticks += 1
	assert_true(board.has_launched(), "the throw never came")
	assert_eq(player.move_manager.current_name, Move.SPRING_BOARD,
		"the throw handed off instead of the move keeping the rise")
	# One tick of the rise's own gravity has come off already.
	assert_gt(player.velocity.y, cfg.jump_z - player.config.pawn.gravity * 0.05,
		"the throw's vertical speed is not the config's (%.2f)" % player.velocity.y)
	assert_almost_eq(player.horizontal_speed(), cfg.xy_min, 0.3,
		"a standing start must be thrown at xy_min (%.2f)" % player.horizontal_speed())
	assert_false(player.is_input_locked(), "the rise did not give input back")
	# The rise stays with the move until the apex.
	while player.velocity.y > 0.0 and ticks < 200:
		assert_eq(player.move_manager.current_name, Move.SPRING_BOARD, "the rise left the move early")
		await step(1)
		ticks += 1
	await step(2)
	assert_eq(player.move_manager.current_name, Move.FALLING,
		"past the apex the move did not hand off to Falling")

func test_the_throw_goes_where_the_camera_looks_at_that_instant() -> void:
	# The owner: turn the view round during the steps and the body is thrown
	# backwards -- a known glitch in the original, copied on purpose.
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	var ticks: int = 0
	while not board.is_stepping() and ticks < 60:
		await step(1)
		ticks += 1
	player.rotation.y += PI  # facing +Z now
	while not board.has_launched() and ticks < 120:
		await step(1)
		ticks += 1
	assert_gt(player.velocity.z, 0.0,
		"thrown along the plants (-Z) instead of the way the camera looks (+Z)")

func test_the_rise_cannot_coil() -> void:
	var player: Player = await _press_jump_at_a_spring_board()
	var board := player.move_manager.move_for(Move.SPRING_BOARD) as SpringBoardMove
	var ticks: int = 0
	while not board.has_launched() and ticks < 120:
		await step(1)
		ticks += 1
	_world["input"].state.crouch_pressed = true
	_world["input"].state.crouch_held = true
	await step(3)
	assert_ne(player.move_manager.current_name, Move.COIL,
		"a spring board coiled: Coil belongs to Jump alone")
