extends TestCase

## Builds a world with a tall wall along the X axis at the given x offset, and
## a player running forward beside it.
func _wall_world(wall_x: float) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 8.0, 60.0)
	shape.shape = box
	wall.add_child(shape)
	tree.root.add_child(wall)
	await step(1)
	wall.global_position = Vector3(wall_x, 4.0, -20.0)
	await step(2)

	world["wall"] = wall
	world["config"] = cfg
	return world

## Runs the player up to speed, then launches it into the air beside the wall.
func _launch_beside_wall(world: Dictionary) -> void:
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	input.press_jump()
	await step(4)

func test_a_fast_jump_beside_a_wall_starts_a_wall_run() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	await _launch_beside_wall(world)

	var attached := false
	for i in 60:
		await step(1)
		if player.state_machine.current_name == &"Wall":
			attached = true
			break
	check(attached, "a fast jump beside a wall should attach, got %s" \
		% player.state_machine.current_name)

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_slow_jump_does_not_start_a_wall_run() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	# Jump from a standstill: no speed, no wall run.
	world["input"].press_jump()

	# NOTE: deviates from the brief, which awaited all 40 ticks and only
	# checked the FINAL state. This player starts at x=0, only 0.45 m from
	# the wall's near face -- well inside wall_reach (0.75 m default) even at
	# rest -- so a defect that dropped the SPEED gate (the actual thing this
	# test names) would still attach briefly (measured: it did, for one tick
	# right after the jump and again a few ticks later) and then fall back
	# out to Ground well before tick 40, leaving the final-state check green
	# for the wrong reason. Watching every tick, the same way
	# test_sliding_cannot_become_a_wall_run already does for its own
	# never-transitions assertion, is what actually catches that.
	var attached_wall := false
	for i in 40:
		await step(1)
		if player.state_machine.current_name == &"Wall":
			attached_wall = true
			break
	check(not attached_wall, \
		"a standing jump must not attach to a wall")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_wall_running_falls_more_slowly_than_free_fall() -> void:
	await step(1)

	# Free fall reference.
	var plain := await _wall_world(40.0)   # wall far away, never attaches
	var plain_player: Player = plain["player"]
	await _launch_beside_wall(plain)
	await step(20)
	var free_fall_vy := plain_player.velocity.y
	plain["wall"].queue_free()
	TestWorld.teardown(plain)
	await step(1)

	# Same launch, but beside a wall.
	var beside := await _wall_world(0.95)
	var wall_player: Player = beside["player"]
	await _launch_beside_wall(beside)
	await step(20)
	var wall_vy := wall_player.velocity.y
	check(wall_player.state_machine.current_name == &"Wall", "precondition: should be wall running")

	check_greater(wall_vy, free_fall_vy, \
		"wall running must resist gravity (wall %f vs free %f)" % [wall_vy, free_fall_vy])

	beside["wall"].queue_free()
	TestWorld.teardown(beside)
	await step(1)

func test_a_wall_jump_pushes_away_from_the_wall_and_upward() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	await _launch_beside_wall(world)

	for i in 60:
		await step(1)
		if player.state_machine.current_name == &"Wall":
			break
	check(player.state_machine.current_name == &"Wall", "precondition: should be wall running")

	world["input"].press_jump()
	await step(3)
	check(player.state_machine.current_name == &"Air", "a wall jump should leave the wall")
	check_greater(player.velocity.y, 0.0, "a wall jump should send the player upward")
	# The wall sits at +X, so the push must be toward -X.
	check(player.velocity.x < 0.0, "a wall jump should push away from the wall")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_the_same_wall_cannot_be_reattached_immediately() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	await _launch_beside_wall(world)

	for i in 60:
		await step(1)
		if player.state_machine.current_name == &"Wall":
			break
	world["input"].press_jump()
	await step(2)

	# Without a cooldown the player would re-attach and climb the same wall
	# forever, which is the classic wall-run exploit.
	for i in 12:
		await step(1)
		check(player.state_machine.current_name != &"Wall", \
			"re-attached to the same wall during the cooldown")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_wall_run_ends_on_its_own() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	await _launch_beside_wall(world)

	for i in 60:
		await step(1)
		if player.state_machine.current_name == &"Wall":
			break
	check(player.state_machine.current_name == &"Wall", "precondition: should be wall running")

	# Move the floor far out of reach before polling for the end of the run.
	# NOTE: deviates from the brief, which polled with the original floor
	# still in place. Wall running weakens gravity (wall_gravity_scale) but
	# never zeroes it, so a defect that strips every one of WallRunState's
	# OWN exit conditions -- the duration cap, the speed floor, losing the
	# wall -- can still pass this test: given the full 400-tick window,
	# weakened-but-nonzero gravity eventually carries the player down onto
	# the ORIGINAL floor regardless, ending the state for a reason that has
	# nothing to do with what this test names. Verified: with those three
	# exit conditions removed (only the floor-landing check left), this test
	# still passed before this fix. Moving the floor out of reach removes
	# that confound, so "ended" can only become true here via one of
	# WallRunState's own exit conditions actually firing.
	world["floor"].global_position.y -= 500.0

	var ended := false
	for i in 400:
		await step(1)
		if player.state_machine.current_name != &"Wall":
			ended = true
			break
	check(ended, "a wall run must end on its own rather than lasting forever")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_sliding_cannot_become_a_wall_run() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	# NOTE: deviates from the brief, which set input.state.crouch_held = true
	# directly here. ScriptedInputSource only raises the crouch_pressed edge
	# inside press_crouch(); GroundState gates slide entry on that edge (not
	# on crouch_held), specifically to prevent held-key strobing -- so a bare
	# state.crouch_held = true never enters Slide at all. This is the exact
	# defect tests/test_slide_state.gd already documents and fixes the same
	# way (see its own note a few lines above its own press_crouch() calls).
	input.press_crouch()

	# The spec forbids Slide -> Wall directly: the player must pass through
	# Ground or Air first. Allowing it lets a slide chain into an infinite
	# speed loop along a wall.
	#
	# NOTE: deviates from the brief, which awaited a separate step(2) for the
	# "should be sliding" precondition BEFORE starting this loop. A defect
	# that checks for a wall on Slide's very FIRST physics_update() call
	# transitions Slide -> Wall within that pre-loop step(2) window -- before
	# the watched loop below ever starts, so `previous` would already read
	# "Wall" on the loop's first iteration and the very transition this test
	# exists to catch would go unobserved. Verified: with that defect
	# injected, the two-loop version above passed cleanly (only the
	# precondition failed) while the actual named assertion never fired.
	# Watching continuously from the crouch press onward, and folding the
	# "did it ever slide" precondition into the SAME loop, closes that gap.
	#
	# Watch the WHOLE window, not just the sliding part — breaking out of the
	# loop as soon as the state stops being Slide would make the assertion
	# vacuous, since "not Wall" is trivially true while the state is Slide.
	var saw_sliding := false
	var saw_wall_directly_from_slide := false
	var previous: StringName = player.state_machine.current_name
	for i in 90:
		await step(1)
		var now: StringName = player.state_machine.current_name
		if now == &"Slide":
			saw_sliding = true
		if previous == &"Slide" and now == &"Wall":
			saw_wall_directly_from_slide = true
			break
		previous = now
	check(saw_sliding, "precondition: should have entered Slide at some point")
	check(not saw_wall_directly_from_slide, \
		"Slide must never transition directly into Wall")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## AirState's ledge-grab check used to be unconditional and first, so a wall
## check placed after it could never win a contested tick. This builds
## geometry where a wall (to the right) and a grabbable ledge (straight ahead)
## are BOTH in reach at once, and asserts wall running wins -- see the
## priority decision and its reasoning in air_state.gd.
func test_a_wall_run_wins_over_a_ledge_grab_when_both_are_in_reach() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]

	# A wall to the player's right, spanning a wide Z range so the fixed test
	# position below sits comfortably inside it. Position set BEFORE
	# add_child(): see tests/test_probes.gd's note on why (a body added at the
	# origin first can transiently overlap the player and get depenetrated).
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.0, 8.0, 60.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.95, 4.0, -20.0)
	tree.root.add_child(wall)
	await step(3)

	# A grabbable ledge directly ahead. Its Z span (about -12.5 to -10.5) sits
	# entirely in front of the player's test Z (-10.0) below, never overlapping
	# it -- the wall's side rays fire at the player's OWN Z each tick, so this
	# block is invisible to them; only the ledge's forward/downward rays ever
	# see it.
	var ledge := StaticBody3D.new()
	var ledge_shape := CollisionShape3D.new()
	var ledge_box := BoxShape3D.new()
	ledge_box.size = Vector3(8.0, 2.6, 2.0)
	ledge_shape.shape = ledge_box
	ledge.add_child(ledge_shape)
	ledge.position = Vector3(0.0, 1.3, -11.5)
	tree.root.add_child(ledge)
	await step(3)

	player.global_position = Vector3(0.0, 0.95, -10.0)
	await step(1)

	var wall_query: Dictionary = player.probes.wall_query()
	var ledge_query: Dictionary = player.probes.ledge_query()
	check(wall_query["valid"], "precondition: a wall must be in reach at this test position")
	check(ledge_query["valid"], "precondition: a ledge must ALSO be in reach at this test position")

	# Fast enough to satisfy wall_min_speed, moving toward the ledge.
	player.velocity = Vector3(0.0, 0.0, -6.0)
	player.state_machine.start(PlayerState.AIR)

	var attached_wall := false
	for i in 5:
		await step(1)
		if player.state_machine.current_name != &"Air":
			attached_wall = player.state_machine.current_name == &"Wall"
			break
	check(attached_wall, \
		"with both a wall and a ledge in reach, wall running must win, got %s" \
		% player.state_machine.current_name)

	wall.queue_free()
	ledge.queue_free()
	TestWorld.teardown(world)
	await step(1)
