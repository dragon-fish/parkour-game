extends TestCase

# The grounded flag must be something states DECLARE, not something inferred
# from a physics call that a scripted-move state never makes.

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	return world

func test_grounded_tracks_the_ground_state() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	check(player.grounded, "a resting player should be grounded")

	world["input"].press_jump()
	await step(4)
	check(not player.grounded, "a jumping player should not be grounded")

	for i in 300:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.grounded, "a landed player should be grounded again")

	TestWorld.teardown(world)
	await step(1)

func test_a_landing_is_reported_exactly_once() -> void:
	var world := await _spawn()
	var player: Player = world["player"]

	world["input"].press_jump()
	await step(4)
	world["input"].release_jump()

	var landings := 0
	for i in 300:
		await step(1)
		if player.last_landing_speed > 0.0 and player.state_machine.current_name == &"Ground":
			landings += 1
			break
	check(landings == 1, "the landing should be reported exactly once")

	# Sitting on the ground must not keep re-reporting a landing.
	await step(60)
	check(player.consume_landing() < 0.0, \
		"resting on the ground must not report further landings")

	TestWorld.teardown(world)
	await step(1)
