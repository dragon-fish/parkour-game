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

## A state that never calls set_grounded() at all. This is the shape of mistake
## the invariant in StateMachine exists for -- P3's WallRun is exactly such a
## state, and forgetting the call there would inherit GroundState's `true`,
## refill coyote time every tick through Player._tick_timers(), and hand the
## player infinite jumps with nothing failing.
class SilentState:
	extends PlayerState

	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		return KEEP

## Closes the hole structurally rather than by convention: an undeclared state
## must NOT inherit whatever the outgoing state left behind.
##
## NOTE: this deliberately provokes the engine error that guard emits. Its exact
## message text is allowlisted in tools/run_tests.ps1 for that reason -- the
## error IS the guard working, the same arrangement
## test_unknown_transition_leaves_the_machine_running already uses.
func test_a_state_that_never_declares_grounded_does_not_inherit_it() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	check(player.grounded, "precondition: a resting player should be grounded")

	var silent := SilentState.new()
	silent.player = player
	silent.config = player.config
	player.state_machine.add_child(silent)
	player.state_machine.register(&"Silent", silent)
	player.state_machine.start(&"Silent")
	check(player.grounded, \
		"precondition: entering the silent state must not itself clear the flag -- the point is that nothing DECLARED it")

	await step(1)
	check(not player.grounded, \
		"a state that never called set_grounded() kept the previous state's `true` -- coyote time refills every tick from it, which is infinite jumps")

	# And it does not spontaneously come back on later ticks either.
	await step(10)
	check(not player.grounded, "the undeclared flag came back after further ticks")

	player.state_machine.start(PlayerState.GROUND)
	TestWorld.teardown(world)
	await step(1)

## Complement to the above: a state that DOES declare must be believed, so the
## guard cannot be satisfied by simply pinning `grounded` to false forever.
func test_a_state_that_declares_grounded_keeps_its_value() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	await step(5)
	check(player.grounded, \
		"a resting player in GroundState -- which declares grounded every tick -- must stay grounded")
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
