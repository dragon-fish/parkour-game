extends ParkourTest

# The wiring between StatusList and the single read points each effect lands
# on. Values (0.5, 2 s) are NOT asserted -- they are tuning dials. What is
# asserted is that the reading changes at all, and that it changes in the one
# place every caller already goes through.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _cap_spec(scale: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = INF
	return s

func test_the_player_ages_its_own_statuses() -> void:
	var p := _player()
	await step(1)
	var s := _cap_spec(0.5)
	s.seconds = 1.0 / 30.0
	p.statuses.apply(s, p, 0)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the status never landed")
	await step(4)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"nothing ticked the list down")

func _block_spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = INF
	return s

# Builds a world (player + input + floor) rather than just the player, for
# the tests below that need to drive real ground movement or a real fall --
# checking a block's effect on WalkingMove/FallingMove requires the moves
# to actually run, not just calling Player's consume_*() directly.
func _world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world

func _run_up_to_slide_speed(world: Dictionary) -> void:
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)
	assert_gt(world["player"].horizontal_speed(), \
		world["player"].config.slide.slide_abort_speed, \
		"did not reach slide entry speed before the block was applied")

func test_a_blocked_jump_never_applies_its_launch_velocity() -> void:
	# THE POINT OF THIS TEST. walking_move.gd sets velocity.y BEFORE it returns
	# JUMP, so refusing the transition in MoveManager.can_enter() would leave
	# the body launched but still Walking. The block has to land on the buffer.
	var p := _player()
	await step(1)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_JUMP), p, 0)
	assert_false(p.consume_jump(), "a blocked jump was still spendable")
	assert_false(p.consume_buffered_jump(), "a blocked buffered jump was spendable")

func test_a_blocked_slide_does_not_enter_slide_while_running_fast() -> void:
	# BLOCK_SLIDE alone, at a speed that would otherwise open Slide -- proves
	# the block actually reaches the transition, not just something adjacent.
	var world := _world()
	var p: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up_to_slide_speed(world)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_SLIDE), p, 0)
	input.press_crouch()
	await step(1)
	await step(1)
	assert_true(p.move_manager.current_name != Move.SLIDE, \
		"a blocked slide still entered Slide")

func test_a_blocked_slide_still_falls_through_to_crouch() -> void:
	# SLIDE blocked, CROUCH free, and fast enough that an unblocked press
	# would have opened Slide instead: the two outlets have to be refused
	# INDEPENDENTLY, so a level that forbids sliding has not also forbidden
	# crouching.
	var world := _world()
	var p: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up_to_slide_speed(world)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_SLIDE), p, 0)
	input.press_crouch()
	await step(1)
	await step(1)
	assert_true(p.move_manager.current_name == Move.CROUCH, \
		"a slide-blocked player running fast did not fall through to Crouch")

func test_a_running_slide_still_reaches_its_crouch_outlet_while_blocked() -> void:
	# THE OUTLET MUST BE PROVEN OPEN. SlideMove hands a key-held exit to
	# CROUCH, and under a low ceiling that is its ONLY exit -- a slide that
	# cannot reach it is a slide with no input that escapes it. BLOCK_SLIDE
	# arrives mid-slide here, which is the status a level would really have
	# in force around a slide it does not want, and the exit still has to
	# open. Nothing can block CROUCH itself; that is what makes this safe.
	var world := _world()
	var p: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up_to_slide_speed(world)
	# press_crouch() leaves crouch_held set; poll() only clears the edge, so
	# the key stays down for the rest of the test without further help.
	input.press_crouch()
	await step(2)
	assert_true(p.move_manager.current_name == Move.SLIDE, "test setup: never entered Slide")
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_SLIDE), p, 0)
	# Stop asking for forward motion so the slide decays into its own
	# spent-and-key-held exit rather than being cut short by a release.
	input.state.move = Vector2.ZERO
	for i in 200:
		await step(1)
		if p.move_manager.current_name != Move.SLIDE:
			break
	assert_eq(p.move_manager.current_name, Move.CROUCH, \
		"a spent slide with the key still held did not reach CROUCH")

func test_a_blocked_roll_lands_without_rolling() -> void:
	var world := _world()
	var p: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	# FallTracker's launch height is only re-based on a genuine set_grounded()
	# call (see FallTracker.reset()), never by place()'s raw teleport -- so
	# the player has to actually FINISH landing here, not merely be given
	# some ticks, or the drop below measures from a stale launch height left
	# over from spawn instead of from this test's own floor contact.
	await step(30)
	assert_true(p.move_manager.current_name == Move.WALKING, "test setup: not walking")
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_SKILL_ROLL), p, 0)
	# A drop past skill_roll_landing_height (2.0 m) but below
	# hard_landing_height (5.3 m), so an unrolled landing still returns to
	# Walking rather than Landing -- keeping the destination check meaningful.
	# Staged the same way test_skill_roll.gd's _land_from() does: raise the
	# body, then re-base FallTracker's launch height to the raised position.
	# FallTracker measures depth below the last GROUNDED height, not below
	# wherever the body was teleported from (fall_tracker.gd), so a raw
	# teleport alone reads back as an ordinary jump returning to its own
	# launch pad -- fall_height stays ~0, never as a genuine fall.
	p.global_position.y += 2.5
	p.fall_tracker.reset(p.global_position.y)
	p.enter_falling_height = p.global_position.y
	await step(1)
	assert_true(p.move_manager.current_name == Move.FALLING, \
		"teleporting up did not send the player airborne")
	input.press_crouch()
	await step(1)
	input.release_crouch()
	var landed := false
	for i in 60:
		await step(1)
		if p.move_manager.current_name == Move.WALKING and i > 0:
			landed = true
			break
	assert_true(landed, "never returned to Walking after the drop")
	assert_almost_eq(p.last_landing_fall_height, 2.5, 0.1, \
		"test setup: the staged fall was not actually ~2.5 m")
	assert_false(p.last_landing_rolled, "a blocked roll still rolled")
