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

## IMPORTANT (review): a wall jump used to read `input.jump_pressed` (a
## single-tick edge) directly. AirState hands off to WallRunState's enter()
## the moment it detects a wall, before this state's own first
## physics_update() ever runs -- so a press made a few ticks before the
## actual attach landed on a tick this state never saw jump_pressed==true on,
## and was silently dropped on the most timing-sensitive move in the game.
## This presses jump while the player is still airborne and away from the
## wall, then arrives at the attach point a few ticks later (well within
## jump_buffer_time), and asserts the wall jump still fires on this state's
## very first update.
func test_a_jump_pressed_shortly_before_reaching_the_wall_still_wall_jumps() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Airborne, far from the wall (x=5.0; the wall's near face sits at x=0.45,
	# well outside wall_reach), moving toward where the wall will be reached.
	player.velocity = Vector3(0.0, 0.0, -6.0)
	player.global_position = Vector3(5.0, 5.0, -10.0)
	player.state_machine.start(PlayerState.AIR)
	# state_machine.start() does not touch `grounded` itself, so it is still
	# whatever this player last declared -- true, left over from resting on
	# the floor a moment ago -- until explicitly cleared. Clearing it stops a
	# stale read from wrongly refilling coyote time on the very next
	# _tick_timers() call, but that is only HALF the landmine: _coyote_timer
	# ITSELF is a separate variable that _tick_timers() only ever DECAYS, and
	# by the time this player was genuinely resting on the floor a moment
	# ago, it had already been legitimately refilled to a full
	# config.coyote_time. In real play that grace gets SPENT the instant an
	# actual jump fires (consume_jump() zeroes both timers together); this
	# hand-built setup never spends it, so it survives as a leftover grace
	# period into the airborne test below. Found this exact way: with only
	# `set_grounded(false)` and no wait, the very next press_jump() still
	# fired an ordinary COYOTE-gated ground-style air jump (velocity.y jumped
	# to ~7) before the wall-buffer logic this test means to isolate ever
	# got a chance to run. Waiting out coyote_time (mirroring
	# tests/test_arena.gd's own `await step(20)` after this exact same
	# state_machine.start(PlayerState.AIR) call) lets it fully decay first.
	player.set_grounded(false)
	await step(10)

	input.press_jump()
	await step(3)
	check(player.state_machine.current_name == &"Air", \
		"precondition: should still be airborne, away from the wall")

	# Arrive beside the wall. This test isolates the BUFFER timing, not the
	# approach, so the position is set directly rather than simulated by
	# running the player over.
	player.global_position.x = 0.0
	await step(1)
	check(player.state_machine.current_name == &"Wall", \
		"precondition: should have attached to the wall")

	await step(1)
	check(player.state_machine.current_name == &"Air", \
		"a jump pressed shortly before reaching the wall should still produce a wall jump")
	check_greater(player.velocity.y, 0.0, "the buffered wall jump should send the player upward")
	check(player.velocity.x < 0.0, "the buffered wall jump should push away from the wall")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## IMPORTANT (review): _normal used to be captured ONCE in enter() and never
## refreshed, even though wall_query() was already being called every tick to
## check validity. Three consequences follow from that: the jump push and
## stick force keep pointing along the STALE entry normal, _along drifts off
## the true tangent, and exit() poisons the reattach cooldown with the wrong
## normal too. The existing wall geometry in this file is perfectly flat for
## its whole length, so none of the other tests can tell a stale normal from
## a fresh one -- they are identical on a flat wall. This proves the refresh
## actually happens by SWAPPING which wall is detected mid-run: attach beside
## a RIGHT-facing wall, then teleport beside a LEFT-facing one with a
## completely different Z span (a deliberately extreme "bend" -- the two
## walls never overlap, so wall_query() genuinely finds a different surface
## rather than a smoothly curved one, but it exercises exactly the same code
## path a true curve would: re-querying and re-deriving _normal/_along every
## tick). Asserts the wall jump off the second wall pushes toward the SECOND
## wall's own away direction (not the stale first one), and that leaving it
## arms the second wall's own cooldown.
func test_wall_run_tracks_the_currently_detected_walls_normal_not_the_entry_one() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Wall A: to the RIGHT, spanning Z in [-15, 5] only -- far enough from
	# wall B below that it cannot still be "seen" once beside wall B.
	var wall_a := StaticBody3D.new()
	var shape_a := CollisionShape3D.new()
	var box_a := BoxShape3D.new()
	box_a.size = Vector3(1.0, 8.0, 20.0)
	shape_a.shape = box_a
	wall_a.add_child(shape_a)
	wall_a.position = Vector3(0.95, 4.0, -5.0)
	tree.root.add_child(wall_a)
	await step(3)

	# Wall B: to the LEFT (an opposite-facing normal), spanning a completely
	# different Z range.
	var wall_b := StaticBody3D.new()
	var shape_b := CollisionShape3D.new()
	var box_b := BoxShape3D.new()
	box_b.size = Vector3(1.0, 8.0, 20.0)
	shape_b.shape = box_b
	wall_b.add_child(shape_b)
	wall_b.position = Vector3(-0.95, 4.0, -30.0)
	tree.root.add_child(wall_b)
	await step(3)

	player.velocity = Vector3(0.0, 0.0, -6.0)
	# y=5.0, not the resting floor height: this test needs the player to stay
	# genuinely AIRBORNE through the 10-tick coyote-decay wait below, not fall
	# through move_and_slide() onto the floor before ever reaching wall A.
	player.global_position = Vector3(0.0, 5.0, -5.0)
	player.state_machine.start(PlayerState.AIR)
	# See the matching comment on test_a_jump_pressed_shortly_before_reaching_
	# the_wall_still_wall_jumps() earlier in this file: wait out the leftover
	# coyote grace from resting on the floor a moment ago before this test
	# ever touches jump.
	player.set_grounded(false)
	await step(10)

	var query_a: Dictionary = player.probes.wall_query()
	check(query_a["valid"] and query_a["side"] == 1, \
		"precondition: should be reading wall A, on the right")

	await step(1)
	check(player.state_machine.current_name == &"Wall", "precondition: should have attached to wall A")

	# Teleport beside wall B instead -- see the note above for why this still
	# exercises the same refresh logic a smoother curve would.
	player.global_position = Vector3(0.0, player.global_position.y, -30.0)
	await step(1)
	check(player.state_machine.current_name == &"Wall", \
		"precondition: should still be wall running, now beside wall B")

	var query_b: Dictionary = player.probes.wall_query()
	check(query_b["valid"] and query_b["side"] == -1, \
		"precondition: should now be reading wall B, on the left")
	check(query_a["normal"].dot(query_b["normal"]) < cfg.wall_same_normal_dot, \
		"precondition: wall A and wall B must have genuinely different normals")

	input.press_jump()
	await step(2)
	check(player.state_machine.current_name == &"Air", "a wall jump off wall B should leave the wall")
	# Wall B sits at -X, so a jump that correctly tracks the CURRENTLY
	# detected wall must push toward +X -- the opposite of what the stale
	# entry-time normal (wall A, at +X) would have produced.
	check(player.velocity.x > 0.0, \
		"a wall jump must push away from the CURRENTLY detected wall, not the one first attached to")
	check(not player.can_attach_wall(query_b["normal"]), \
		"leaving wall B must arm wall B's OWN cooldown, not a stale copy of wall A's")

	wall_a.queue_free()
	wall_b.queue_free()
	TestWorld.teardown(world)
	await step(1)

## IMPORTANT (review): the Wall -> Ground transition (running a wall down onto
## the floor -- an ordinary way for a wall run to end) had no test at all.
## Reverting the per-tick grounded declaration to enter()-only silently killed
## this transition (grounded never becomes true again) while the suite stayed
## green, since nothing exercised it. Starts the player airborne right at the
## normal resting floor height beside the wall, so weakened wall gravity
## carries the body onto the floor within a handful of ticks -- comfortably
## inside wall_max_duration (1.5 s = 90 ticks) and above wall_exit_speed, so
## landing is what ends this run, not either of those other exit paths.
func test_a_wall_run_can_end_by_landing_on_the_floor() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]

	player.velocity = Vector3(0.0, 0.0, -6.0)
	player.global_position = Vector3(0.0, 0.95, -10.0)
	player.state_machine.start(PlayerState.AIR)
	# See the matching comment on the buffered-jump test above: start() leaves
	# `grounded` stale (true, from resting on the floor a moment ago), which
	# would otherwise wrongly refill coyote time for one tick. Harmless here
	# since nothing in this test presses jump, but cleared anyway so this
	# forced-AIR setup is not a landmine for whoever edits it next.
	player.set_grounded(false)
	await step(1)
	check(player.state_machine.current_name == &"Wall", "precondition: should have attached to the wall")

	var previous: StringName = player.state_machine.current_name
	var landed_on_ground := false
	var went_via_air := false
	for i in 30:
		await step(1)
		var now: StringName = player.state_machine.current_name
		if previous == &"Wall" and now == &"Air":
			went_via_air = true
		if now == &"Ground":
			landed_on_ground = true
			break
		previous = now
	check(landed_on_ground, \
		"a wall run over the floor must be able to end by landing on Ground")
	check(not went_via_air, \
		"landing on the floor should transition Wall -> Ground directly, not through Air")
	check(player.grounded, "landing on Ground must leave grounded declared true")

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

## IMPORTANT (review): a single {normal, cooldown} slot on Player was found to
## be bypassable in any corner -- leaving wall A, then briefly touching a
## genuinely different (perpendicular) wall B, would overwrite A's entry the
## moment B's own exit rekeyed the cooldown, making A immediately
## re-attachable one tick later. In a corner this is unbounded vertical
## climbing. This drives a REAL attach-and-detach on wall A (so its cooldown
## is armed exactly the way gameplay arms it, through WallRunState.exit()),
## then simulates briefly touching wall B through the same public
## note_wall_detach() hook WallRunState.exit() itself calls -- physically
## maneuvering the player into a second real wall for one tick is orthogonal
## to what this bug is about, which is Player's own cooldown bookkeeping, not
## wall detection -- and asserts wall A is still refused afterward.
func test_leaving_a_wall_and_briefly_touching_a_perpendicular_one_does_not_clear_the_first_walls_cooldown() -> void:
	await step(1)
	var world := await _wall_world(0.95)
	var player: Player = world["player"]
	await _launch_beside_wall(world)

	for i in 60:
		await step(1)
		if player.state_machine.current_name == &"Wall":
			break
	check(player.state_machine.current_name == &"Wall", "precondition: should be wall running")

	# Capture wall A's real normal before leaving it, so the refusal check
	# below asks about the EXACT wall that was left, not an assumed one.
	var wall_a_query: Dictionary = player.probes.wall_query()
	check(wall_a_query["valid"], "precondition: should still be reading a valid wall normal")
	var normal_a: Vector3 = wall_a_query["normal"]

	world["input"].press_jump()
	await step(2)
	check(player.state_machine.current_name != &"Wall", \
		"precondition: the wall jump should have left the wall")
	check(not player.can_attach_wall(normal_a), \
		"precondition: wall A's own cooldown should be armed immediately after leaving it")

	# Briefly touch a genuinely different (perpendicular) wall B.
	var normal_b := Vector3(0.0, 0.0, 1.0)
	check(normal_a.dot(normal_b) < player.config.wall_same_normal_dot, \
		"precondition: wall B must be genuinely different from wall A for this test to mean anything")
	player.note_wall_detach(normal_b)

	check(not player.can_attach_wall(normal_a), \
		"leaving a perpendicular wall B must not clear wall A's own cooldown")

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
	# See the matching comment on test_a_jump_pressed_shortly_before_reaching_
	# the_wall_still_wall_jumps() earlier in this file: start() leaves
	# `grounded` stale (true, from resting on the floor a moment ago), which
	# would otherwise wrongly refill coyote time for one tick. Harmless here
	# since nothing in this test presses jump, but cleared anyway so this
	# forced-AIR setup is not a landmine for whoever edits it next.
	player.set_grounded(false)

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
