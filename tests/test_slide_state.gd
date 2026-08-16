extends TestCase

func _running_world(cfg: MovementConfig) -> Dictionary:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	return world

func test_crouching_at_speed_enters_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", \
		"pressing crouch while running should enter Slide, got %s" % player.state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_slide_gives_a_one_time_speed_boost() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var before := player.horizontal_speed()
	world["input"].press_crouch()
	await step(2)
	var just_after_entry := player.horizontal_speed()
	check_greater(just_after_entry, before, "entering a slide must add speed")

	# A per-tick boost would keep adding speed for as long as the slide lasts.
	# The boost is one-time, so speed from here on can only ever decay under
	# slide_friction — sampling later in the same slide must show a DROP, not
	# more growth.
	await step(20)
	check(player.state_machine.current_name == &"Slide", \
		"precondition: should still be sliding for the decay check to mean anything")
	var later := player.horizontal_speed()
	check(later < just_after_entry, \
		"speed grew further into the slide (%f -> %f); the boost must be one-time, not per-tick" \
		% [just_after_entry, later])
	TestWorld.teardown(world)
	await step(1)

func test_crouching_from_a_standstill_does_not_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"a standing crouch must not start a slide")
	TestWorld.teardown(world)
	await step(1)

func test_slide_decays_and_returns_to_ground() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Hold crouch and let friction do its work.
	for i in 600:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.state_machine.current_name == &"Ground", \
		"a slide must eventually decay back to Ground")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_crouch_ends_the_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	world["input"].release_crouch()
	await step(5)
	check(player.state_machine.current_name == &"Ground", \
		"releasing crouch should end the slide")
	TestWorld.teardown(world)
	await step(1)

func test_holding_crouch_does_not_strobe_slide() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_crouch()

	# A held key produces exactly one press edge. If Slide entry keyed off
	# crouch_held instead of that edge, every Slide->Ground decay while the
	# key is still down would immediately re-cross slide_entry_speed and
	# re-enter Slide, strobing for as long as the key is held.
	var slide_entries := 0
	var was_sliding := false
	for i in 150:
		await step(1)
		var sliding: bool = player.state_machine.current_name == &"Slide"
		if sliding and not was_sliding:
			slide_entries += 1
		was_sliding = sliding

	check(slide_entries <= 1, \
		"holding crouch while running must not strobe in and out of Slide (entered %d times)" \
		% slide_entries)
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_is_shorter_while_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing := shape.height
	world["input"].press_crouch()
	await step(2)
	check_greater(standing, shape.height, "the capsule must shrink while sliding")

	world["input"].release_crouch()
	await step(10)
	check_approx(shape.height, standing, 0.001, "the capsule must return to standing height")
	TestWorld.teardown(world)
	await step(1)

func test_the_capsule_bottom_does_not_move_when_shrinking() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var shape := shape_node.shape as CapsuleShape3D

	var bottom_before := shape_node.position.y - shape.height * 0.5
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", \
		"precondition: should be sliding, or this check passes vacuously")
	var bottom_after := shape_node.position.y - shape.height * 0.5
	check_approx(bottom_after, bottom_before, 0.001, \
		"shrinking the capsule must keep its bottom in place, or footing shifts")
	TestWorld.teardown(world)
	await step(1)

func test_sliding_off_an_edge_enters_air() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Remove the floor from under the slide.
	world["floor"].global_position = Vector3(0.0, -80.0, 0.0)
	await step(5)
	check(player.state_machine.current_name == &"Air", \
		"leaving the ground mid-slide must enter Air")
	TestWorld.teardown(world)
	await step(1)

func test_a_low_ceiling_keeps_the_player_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	# NOTE: deviates from the brief, which set world["input"].state.crouch_held
	# = true directly here. ScriptedInputSource only raises the crouch_pressed
	# edge inside press_crouch(); GroundState gates slide entry on that edge
	# (not on crouch_held) specifically to prevent held-key strobing, so a bare
	# state.crouch_held = true never enters Slide at all. Verified by running
	# the brief's code verbatim: the precondition below failed regardless of
	# the headroom fix, i.e. the test could never go green. Every other slide
	# entry in this file already uses press_crouch(); matching that.
	world["input"].press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Drop a slab just above the sliding capsule, across the player's path.
	# NOTE: deviates from the brief, which parented `shape` and added `ceiling`
	# to the tree BEFORE setting its position, leaving the (still zero-position)
	# 40x40 slab briefly overlapping the floor and the player's actual collider
	# at the world origin for one physics frame. Since ceiling.position is set
	# before add_child() below, no such frame at the origin. Verified by
	# reproducing the brief's ordering standalone: that transient overlap
	# physically shoves the player upward, is_on_floor() flips false, and
	# SlideState exits straight to Air — which lands on Ground the very next
	# frame WITHOUT ever consulting has_headroom() (Air->Ground is
	# intentionally out of this gate's scope). So the observed "stood up
	# into the ceiling" failure was this ordering bug, not a missing gate.
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.5, 40.0)
	shape.shape = box
	ceiling.add_child(shape)
	ceiling.position = player.global_position + Vector3(0.0, 0.45, 0.0)
	tree.root.add_child(ceiling)
	await step(1)

	world["input"].release_crouch()
	await step(10)
	check(player.state_machine.current_name == &"Slide", \
		"the player must not stand up into a ceiling, got %s" % player.state_machine.current_name)

	ceiling.queue_free()
	await step(2)
	await step(20)
	check(player.state_machine.current_name == &"Ground", \
		"once the ceiling is gone the player should stand up")

	TestWorld.teardown(world)
	await step(1)

## Parks a slab just above the sliding capsule, across the player's path, so
## has_headroom() is false and every route back to Ground is gated shut. Same
## construction (and the same ordering care) as
## test_a_low_ceiling_keeps_the_player_sliding above.
func _add_ceiling_over(player: Player) -> StaticBody3D:
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.5, 80.0)
	shape.shape = box
	ceiling.add_child(shape)
	ceiling.position = player.global_position + Vector3(0.0, 0.45, 0.0)
	tree.root.add_child(ceiling)
	return ceiling

func test_a_spent_slide_under_a_ceiling_can_still_crawl_out() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	var ceiling := _add_ceiling_over(player)
	await step(1)

	# Let the slide spend itself completely with no input at all. Friction only
	# ever removes speed and every exit to standing is gated on headroom, so
	# without the crawl this is a terminal state: horizontal speed reaches zero
	# and nothing in Slide can ever generate any again.
	input.state.move = Vector2.ZERO
	for i in 240:
		await step(1)
		if player.horizontal_speed() < 0.01:
			break
	check(player.state_machine.current_name == &"Slide", \
		"precondition: a blocked slide must not have stood up, got %s" % player.state_machine.current_name)
	check(player.horizontal_speed() < 0.5, \
		"precondition: the slide should have decayed to a stop, speed = %f" % player.horizontal_speed())

	# Now hold forward. The player is still stuck under the roof, but must be
	# able to move out from under it.
	var stuck_at: Vector3 = player.global_position
	input.state.move = Vector2(0.0, 1.0)
	await step(60)
	var travelled: float = Vector2(player.global_position.x - stuck_at.x, \
		player.global_position.z - stuck_at.z).length()
	check_greater(travelled, 0.5, \
		"a spent slide under a ceiling made no progress under forward input — the player is stranded at %s in state %s" \
		% [player.global_position, player.state_machine.current_name])

	ceiling.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_jumping_out_of_a_blocked_slide_is_refused() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	var ceiling := _add_ceiling_over(player)
	await step(1)

	# The jump branch exits to Air, and exit() restores the STANDING capsule on
	# the way — straight into the roof. Physically you cannot jump into a
	# ceiling either, so the press must simply not take.
	input.press_jump()
	await step(5)
	check(player.state_machine.current_name == &"Slide", \
		"a jump under a ceiling must not leave the slide, got %s" % player.state_machine.current_name)
	check(player.velocity.y <= 0.1, \
		"a jump under a ceiling must not launch the player, velocity.y = %f" % player.velocity.y)

	ceiling.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_sliding_off_an_edge_under_a_ceiling_does_not_restore_the_capsule() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing := player.standing_height()

	input.press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	var ceiling := _add_ceiling_over(player)
	await step(1)
	check_approx(shape.height, cfg.slide_capsule_height, 0.001, \
		"precondition: the capsule should be crouched while sliding")

	# Take the ground away. The off-edge exit returns AIR whether or not there
	# is headroom — a player who walks off a ledge falls, ceiling or not — so
	# this path cannot be headroom-gated the way the jump path is. exit() must
	# therefore not restore the standing capsule here: it would spawn a 1.8 m
	# body inside the roof that is still directly overhead.
	world["floor"].global_position = Vector3(0.0, -80.0, 0.0)
	await step(3)
	check(player.state_machine.current_name == &"Air", \
		"precondition: leaving the ground mid-slide must enter Air, got %s" \
		% player.state_machine.current_name)
	check(shape.height < standing, \
		"the capsule stood back up into the ceiling on the way out of the slide (height %f)" % shape.height)

	# ...and it must come back on its own the moment there is room, or the
	# player is left permanently crouched.
	ceiling.queue_free()
	await step(10)
	check_approx(shape.height, standing, 0.001, \
		"the standing capsule was never restored once the ceiling was gone (height %f)" % shape.height)

	TestWorld.teardown(world)
	await step(1)

func test_a_long_covered_downslope_cannot_outrun_the_slide_speed_cap() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	# The tuning panel builds every slider's range as default * 3, so this is a
	# position a human can actually drag to.
	cfg.slide_slope_accel = cfg.slide_slope_accel * 3.0

	var world := TestWorld.build(tree, cfg)
	await step(1)
	var player: Player = world["player"]
	var floor_body: StaticBody3D = world["floor"]
	var slope := deg_to_rad(-30.0)
	floor_body.rotation.x = slope
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	player.global_position = Vector3(0.0, 1.2, 0.0)
	await step(30)

	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(60)
	input.press_crouch()
	await step(2)
	check(player.state_machine.current_name == &"Slide", "precondition: should be sliding")

	# Roof the whole slope, parallel to it. slide_max_duration is gated on
	# headroom, so under cover the slide has no time limit either — which is
	# exactly the case where nothing but slide_max_speed bounds it. Added after
	# the capsule has already shrunk, so the slab never intersects a standing
	# body. Offset along the slope's own normal by half the floor thickness +
	# the clearance + half the roof thickness.
	var normal := Vector3(0.0, cos(slope), sin(slope))
	var ceiling := StaticBody3D.new()
	var ceiling_shape := CollisionShape3D.new()
	var ceiling_box := BoxShape3D.new()
	ceiling_box.size = Vector3(40.0, 1.0, 200.0)
	ceiling_shape.shape = ceiling_box
	ceiling.add_child(ceiling_shape)
	ceiling.rotation.x = slope
	ceiling.position = floor_body.global_position + normal * 2.3
	tree.root.add_child(ceiling)
	await step(1)

	var peak := 0.0
	for i in 180:
		await step(1)
		peak = maxf(peak, player.horizontal_speed())
	check(player.state_machine.current_name == &"Slide", \
		"precondition: the covered slide should still be running, got %s" \
		% player.state_machine.current_name)
	check(peak <= cfg.slide_max_speed + 0.1, \
		"a long covered downslope accelerated past the cap (peak %f vs slide_max_speed %f)" \
		% [peak, cfg.slide_max_speed])
	# ...and the run has to actually press against the cap, or this passes by
	# never getting near it and would not notice the cap being removed.
	check_greater(peak, cfg.slide_max_speed - 0.5, \
		"the slide never reached the cap, so this test proves nothing about it (peak %f)" % peak)

	ceiling.queue_free()
	TestWorld.teardown(world)
	await step(1)

## Runs the player up to speed, slides, and returns how much horizontal speed
## survives `ticks` frames of that slide. `slope_deg` tilts the floor so the
## slide runs DOWN it; 0 leaves the floor flat. The slope is built here rather
## than taken from the arena so the comparison is like-for-like apart from the
## tilt.
func _speed_after_sliding(slope_deg: float, ticks: int) -> float:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	var player: Player = world["player"]
	var floor_body: StaticBody3D = world["floor"]

	# Tilt about X so that running toward -Z (the player's default facing) goes
	# DOWNHILL. Verified by the same sign convention the arena ramps use: a
	# positive rotation.x raises the -Z end, so a descent needs a negative one.
	floor_body.rotation.x = deg_to_rad(-slope_deg)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	player.global_position = Vector3(0.0, 1.2, 0.0)
	await step(30)

	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	input.press_crouch()
	await step(2)
	var sliding: bool = player.state_machine.current_name == &"Slide"
	for i in ticks:
		await step(1)
	var speed := player.horizontal_speed()
	check(sliding, "precondition: _speed_after_sliding(%f) never entered Slide" % slope_deg)
	TestWorld.teardown(world)
	await step(1)
	return speed

func test_sliding_downhill_keeps_more_speed_than_sliding_on_the_flat() -> void:
	await step(1)
	# Sampled part-way into the slide, while both are still sliding, so this
	# compares the DECAY of the two rather than two end states.
	var flat := await _speed_after_sliding(0.0, 45)
	var downhill := await _speed_after_sliding(20.0, 45)
	check_greater(downhill, flat, \
		"a slide down a slope must keep more speed than the same slide on flat ground (downhill %f vs flat %f)" \
		% [downhill, flat])

func test_a_crouch_pressed_just_before_landing_opens_a_slide_on_touchdown() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)

	# Lift the runner without touching its horizontal motion, then press crouch
	# on the way down and HOLD it through the impact — which is what a roll is.
	# The press edge fires in mid-air, so before the crouch buffer existed it
	# was gone by the time GroundState looked, and the player had to release
	# and re-tap after landing for the roll-into-slide chain to work at all.
	player.global_position = Vector3(player.global_position.x, 3.2, player.global_position.z)
	await step(2)

	var pressed := false
	var slid := false
	var landed := false
	for i in 300:
		await step(1)
		if not pressed and player.global_position.y < 1.6:
			input.press_crouch()
			pressed = true
		if player.state_machine.current_name == &"Slide":
			slid = true
		if player.last_landing_speed > 0.0:
			landed = true
		if slid:
			break
	check(pressed, "precondition: the test never got close enough to the ground to press crouch")
	check(landed, "precondition: the player never landed")
	check(player.last_landing_rolled, \
		"precondition: crouch was not held through the impact, so this was not a roll")
	check(slid, \
		"a crouch held through a roll must chain into a slide on touchdown, state = %s, speed = %f" \
		% [player.state_machine.current_name, player.horizontal_speed()])
	TestWorld.teardown(world)
	await step(1)

## The spec forbids a direct Slide -> WallRun transition (section 5), and wall
## running arrives next phase. Nothing at runtime would notice such a
## transition being added, so this asserts it structurally: of every state name
## PlayerState declares, slide_state.gd may only ever mention Ground and Air.
## Adding a new state and returning it from SlideState fails here — as does
## merely naming it in a comment, which is a deliberate false positive: a
## tripwire is worth more than a clean read.
func test_slide_can_only_reach_ground_and_air() -> void:
	await step(1)
	var source := FileAccess.get_file_as_string("res://scripts/player/states/slide_state.gd")
	check(source.length() > 0, "could not read slide_state.gd")

	var state_script: GDScript = load("res://scripts/player/states/player_state.gd")
	var referenced: Array[String] = []
	for key in state_script.get_script_constant_map().keys():
		var constant_name := String(key)
		if constant_name == "KEEP":
			continue
		var pattern := RegEx.new()
		pattern.compile("\\b%s\\b" % constant_name)
		if pattern.search(source) != null:
			referenced.append(constant_name)
	referenced.sort()
	var expected: Array[String] = ["AIR", "GROUND"]
	check(referenced == expected, \
		"Slide must be able to reach exactly Ground and Air, but slide_state.gd references %s" \
		% str(referenced))

## Companion tripwire to the test above, closing the one hole it has. That one
## enumerates PlayerState's constant map and looks for each name in the source,
## so it cannot see a transition written as a bare StringName —
## `return &"WallRun"` needs no PlayerState constant to exist, and the loop
## therefore has nothing to search for. This one reads the RETURN statements
## themselves, so the set of states reachable from Slide is pinned regardless of
## how a future author spells the target.
##
## Written NOW, before wall running exists, on purpose: the spec forbids a
## direct Slide -> WallRun transition (section 5), and a tripwire laid before
## the temptation arrives is worth more than one written after someone has
## already reached for it. Updating the expected set below is meant to be a
## deliberate act with a spec argument attached, not a red-test cleanup.
func test_slide_returns_only_ground_air_or_keep() -> void:
	await step(1)
	var source := FileAccess.get_file_as_string("res://scripts/player/states/slide_state.gd")
	check(source.length() > 0, "could not read slide_state.gd")

	var targets: Dictionary = {}

	# Constant-style returns: `return GROUND`, `return AIR`, `return KEEP`, and
	# whatever a later phase adds. Restricted to SCREAMING_CASE identifiers so
	# ordinary value returns (`return _crawling`, `return _direction`) are not
	# mistaken for transitions.
	var identifier := RegEx.new()
	identifier.compile("return\\s+([A-Z][A-Z0-9_]*)\\b")
	for found_match in identifier.search_all(source):
		targets[found_match.get_string(1)] = true

	# ...and literal-style ones: `return &"WallRun"` or `return "WallRun"`.
	var literal := RegEx.new()
	literal.compile("return\\s+&?\"([^\"]*)\"")
	for found_match in literal.search_all(source):
		targets['&"%s"' % found_match.get_string(1)] = true

	var returned: Array = targets.keys()
	returned.sort()
	var allowed := ["AIR", "GROUND", "KEEP"]
	check(returned == allowed, \
		"SlideState returns %s; the spec allows it to reach only Ground and Air (plus KEEP). A direct Slide -> WallRun transition is forbidden by spec section 5 — if this set is meant to change, change the spec first" \
		% str(returned))

func test_the_camera_drops_while_sliding() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _running_world(cfg)
	var player: Player = world["player"]
	var rig: CameraRig = player.get_node("CameraRig")
	var standing_y := rig.position.y

	# Same deviation as test_a_low_ceiling_keeps_the_player_sliding above:
	# press_crouch() is required to actually enter Slide.
	world["input"].press_crouch()
	await step(20)
	check(rig.position.y < standing_y, "the camera must drop while sliding")

	# A direction-only check would still pass a regression where the drop is
	# capped at a single frame's worth of crouch_lerp_speed * delta instead of
	# actually reaching slide_camera_drop (exactly the bug the persistent
	# _crouch_offset in CameraRig fixes). 20 steps is well past the time
	# crouch_lerp_speed needs to cover slide_camera_drop, so the drop should
	# have fully settled by now — assert its settled SIZE against config, not
	# a pinned number, so this still passes under tuning.
	check_approx(standing_y - rig.position.y, cfg.slide_camera_drop, 0.01, \
		"the camera must settle at the full configured slide_camera_drop, not just move in that direction")

	world["input"].release_crouch()
	await step(60)
	check_approx(rig.position.y, standing_y, 0.01, "the camera must rise back after the slide")
	TestWorld.teardown(world)
	await step(1)
