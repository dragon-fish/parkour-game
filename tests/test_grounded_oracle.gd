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

	# A landing is, by construction, exactly an Air -> Ground transition:
	# AirState.physics_update() is the only place notify_landed() is ever
	# called, and it is called precisely when is_on_floor() goes true. Count
	# THAT — via the state machine's own signal, over the whole window,
	# without stopping at the first sighting — rather than polling a value
	# that only ever gets sampled once. A loop that breaks the instant it
	# spots a landing can never notice a second one; this can.
	#
	# The counters are single-element Arrays, not plain values: GDScript
	# lambdas capture local variables by VALUE, so `landings += 1` inside the
	# closure below would silently mutate a copy and never touch the one this
	# function reads. An Array is a reference type, so `landings[0] += 1`
	# mutates the same object both sides see.
	#
	# landing_speed is sampled INSIDE the callback, at the instant of the
	# transition — i.e. before GroundState.physics_update() has run even
	# once (state_changed fires from within AirState's own physics_update(),
	# a full tick before Ground's first update). Sampling any later would let
	# a buggy state overwrite last_landing_speed before this test ever reads
	# the real value, silently defeating the check below.
	var landings := [0]
	var landing_speed := [-1.0]
	player.state_machine.state_changed.connect(func(from: StringName, to: StringName) -> void:
		if from == &"Air" and to == &"Ground":
			landings[0] += 1
			landing_speed[0] = player.last_landing_speed)

	world["input"].press_jump()
	await step(4)
	world["input"].release_jump()
	await step(300)
	check(landings[0] == 1, \
		"the landing should be reported exactly once, saw %d Air->Ground transition(s)" % landings[0])

	# Sitting on the ground afterwards must not keep re-reporting a landing —
	# neither as a further Air->Ground transition, nor as the recorded impact
	# speed silently changing underneath the one already reported. The second
	# half matters even though transitions alone stay flat: a state that
	# called notify_landed() again without ever leaving Ground would trip
	# this without tripping the transition count above.
	await step(60)
	check(landings[0] == 1, \
		"resting on the ground must not report further landings, saw %d Air->Ground transition(s)" \
			% landings[0])
	check_approx(player.last_landing_speed, landing_speed[0], 0.001, \
		"resting on the ground changed the recorded landing speed — a landing was reported again")

	TestWorld.teardown(world)
	await step(1)
