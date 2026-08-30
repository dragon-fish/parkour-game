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
