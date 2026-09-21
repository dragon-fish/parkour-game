extends ParkourTest

# LayOnGroundMove: on the back, and up again when asked. The three ways in and
# the one way out; how far it slides and how long it takes are dials and are
# not asserted.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []


func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()


func _standing_world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	world["player"].global_position = Vector3(0.0, 1.45, 0.0)
	await step(30)
	return world


func _knock_down(p: Player) -> void:
	var s := StatusSpec.new()
	s.effect = Status.Effect.KNOCKDOWN
	s.seconds = 0.1
	p.apply_status(s, self, 0, true)


## A jump with `forward` held on the stick, turned round in the air, followed
## to the floor. Returns the move the landing chose.
func _turned_jump(forward: float) -> StringName:
	var world := await _standing_world()
	var p: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, forward)
	await step(40)
	input.press_jump()
	await step(2)
	input.release_jump()
	await step(6)
	assert_false(p.grounded, "test setup: the body never left the floor")
	input.hold_move(0.0, 0.0)
	input.press_turn()
	for i in 180:
		await step(1)
		if p.grounded:
			break
	return p.move_manager.current_name


func test_a_knock_down_puts_the_body_on_its_back_and_a_key_gets_it_up() -> void:
	var world := await _standing_world()
	var p: Player = world["player"]
	_knock_down(p)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LAY_ON_GROUND, "the knock-down did not reach the move")
	assert_false(p.statuses.has(Status.Effect.KNOCKDOWN), "and was not spent on the way")
	await step(600)
	assert_eq(p.move_manager.current_name, Move.LAY_ON_GROUND, "nobody asked, and the body got up on its own")
	assert_true(p.grounded, "lying on a floor is grounded")
	(world["input"] as ScriptedInputSource).hold_move(0.0, 1.0)
	await step(2)
	assert_true((p.move_manager.move_for(Move.LAY_ON_GROUND) as LayOnGroundMove).is_rising(), "forward did not start the get-up")
	for i in 600:
		await step(1)
		if p.move_manager.current_name != Move.LAY_ON_GROUND:
			break
	assert_eq(p.move_manager.current_name, Move.WALKING, "the get-up ends on its feet")
	assert_almost_eq(p.current_capsule_height(), p.standing_height(), 0.01, "at its standing height")


func test_a_blow_that_comes_with_the_knock_down_is_still_charged() -> void:
	var world := await _standing_world()
	var p: Player = world["player"]
	var before: float = p.health.hp
	var blow := StatusSpec.new()
	blow.effect = Status.Effect.STAGGER
	blow.amount = 20.0
	blow.seconds = 0.1
	p.apply_status(blow, self, 0, true)
	_knock_down(p)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LAY_ON_GROUND, "down, not into the landing's lockout")
	assert_almost_eq(p.health.hp, before - 20.0, 0.01, "and the blow cost what it costs")


func test_a_forward_jump_turned_round_in_the_air_lands_on_its_back() -> void:
	assert_eq(await _turned_jump(1.0), Move.LAY_ON_GROUND)


func test_a_standing_jump_turned_round_lands_on_its_feet() -> void:
	assert_ne(await _turned_jump(0.0), Move.LAY_ON_GROUND)


func test_a_backward_jump_turned_round_lands_on_its_feet() -> void:
	assert_ne(await _turned_jump(-1.0), Move.LAY_ON_GROUND)


func test_no_room_to_stand_gets_up_into_a_crouch() -> void:
	var world := await _standing_world()
	var p: Player = world["player"]
	_knock_down(p)
	await step(60)
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.2, 6.0)
	shape.shape = box
	roof.add_child(shape)
	get_tree().root.add_child(roof)
	roof.global_position = Vector3(p.global_position.x, p.global_position.y - p.current_capsule_height() * 0.5 + 1.2, p.global_position.z)
	await step(2)
	(world["input"] as ScriptedInputSource).hold_move(0.0, 1.0)
	await step(3)
	roof.queue_free()
	assert_eq(p.move_manager.current_name, Move.CROUCH, "under a 1.2 m roof the body crouches out, it does not stand into the roof")
