extends ParkourTest

# The first slice of the faithful port, end to end: the original's frame
# (controller, actions, automatic transitions, physics, TickSpecial), its
# SetMove semantics on a real body, and the results its formulas give in
# closed form. [ME:CONFIRMED decompile 15, N1, N2, N4] Structural invariants
# and the original's own arithmetic -- no tuning values.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()
	await step(1)

func _world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(20)
	return world

## A platform of `height` metres to walk off, its +Z edge at z = 0, standing
## on the fixture's floor.
func _ledge(world: Dictionary, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, height, 10.0)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, height * 0.5, -5.0)
	world["ledge"] = body
	return body

func _free_ledge(world: Dictionary) -> void:
	if world.has("ledge"):
		(world["ledge"] as Node).queue_free()

## [ME:CONFIRMED emulated 15.7] BaseJumpZ 630 uu/s under the falling
## integrator's doubled gravity: apex 630^2 / 3200 = 124 uu, airtime
## 2 * 630 / 1600 = 0.7875 s.
func test_a_flat_jump_peaks_at_1_24_m_and_lands_after_0_7875_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var y0: float = player.global_position.y
	var top: float = y0
	input.press_jump()
	var frames := 0
	for i in 90:
		await step(1)
		frames += 1
		top = maxf(top, player.global_position.y)
		if frames > 2 and player.physics == Move.PHYS_WALKING:
			break
	assert_almost_eq(top - y0, 1.24, 0.005, "the flat jump's apex")
	# Landing is found on the first frame whose sub-step reaches the floor:
	# 0.7875 s lies between frames 47 and 48.
	assert_true(frames == 48, "landed after %d frames, not the 48th" % frames)

## The same jump from where a straight-down landing left the body: standing
## still, the walk reuses its floor and never lifts it to its hover, so it
## rests closer to the floor than Godot's safe margin. The depenetration
## MoveActor does not have must not be read as part of the take-off.
func test_a_jump_from_a_landing_at_rest_peaks_at_1_24_m() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	player.move_manager.start(Move.FALLING)
	player.global_position.y += 1.0
	for i in 60:
		await step(1)
		if player.physics == Move.PHYS_WALKING:
			break
	await step(10)
	var y0: float = player.global_position.y
	var top: float = y0
	input.press_jump()
	for i in 30:
		await step(1)
		top = maxf(top, player.global_position.y)
	assert_almost_eq(top - y0, 1.24, 0.005, "the jump's apex from a landing at rest")

## [ME:CONFIRMED decompile N2 §6] Jump keeps PHYS_Walking until StartJump,
## which sets Falling -- and setting Falling stamps EnterFallingHeight.
func test_the_jump_switches_to_falling_physics_and_stamps_the_take_off_height() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var y0: float = player.global_position.y
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP)
	assert_eq(player.physics, Move.PHYS_FALLING)
	assert_almost_eq(player.enter_falling_height, y0, 0.001, "EnterFallingHeight is not the take-off height")
	assert_almost_eq(player.last_jump_location.y, y0, 0.001)

## [ME:CONFIRMED decompile N4 §2.5] Jump's bCheckExitToFalling at -400 uu/s,
## asked in PrePhysics: the frame that starts below it is the frame Falling
## takes over. Falling records Jump as the move it came out of.
func test_a_jump_hands_to_falling_below_minus_400_uu_per_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_jump()
	var history: Array = []
	for i in 60:
		history.append(player.velocity.y)
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING, "the jump never became a fall")
	var at_switch: float = history[history.size() - 1]
	var before_switch: float = history[history.size() - 2]
	assert_lt(at_switch, -4.0, "Falling took over above -400 uu/s")
	assert_true(before_switch >= -4.0, "Jump ran a frame past -400 uu/s (%.3f)" % before_switch)
	var falling: Move = player.move_manager.move_for(Move.FALLING)
	assert_eq(falling.previous_move, Move.JUMP)

## [ME:CONFIRMED decompile 15.4, 15.7] Every landing is Landing, and an
## ordinary one sets Walking from inside Landing's own StartMove: both changes
## happen on the touchdown frame, and Walking's OldMovementState is Landing.
func test_an_ordinary_landing_passes_through_landing_into_walking_on_one_frame() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var changes: Array = []
	var frame := [0]
	player.move_manager.move_changed.connect(func(from: StringName, to: StringName) -> void:
		changes.append([frame[0], from, to]))
	input.press_jump()
	for i in 90:
		await step(1)
		frame[0] += 1
		if player.move_manager.current_name == Move.WALKING and frame[0] > 2:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING)
	assert_eq(player.old_movement_state, Move.LANDING, "Walking was not entered from Landing")
	var into_landing: Array = changes.filter(func(c: Array) -> bool: return c[2] == Move.LANDING)
	var into_walking: Array = changes.filter(func(c: Array) -> bool: return c[2] == Move.WALKING)
	assert_eq(into_landing.size(), 1)
	assert_eq(into_walking.size(), 1)
	assert_eq(into_landing[0][0], into_walking[0][0], "Landing outlived its frame")
	assert_eq(player.physics, Move.PHYS_WALKING)

## [ME:CONFIRMED decompile, ini] Jump has no RedoMoveTime of its own: it keeps
## TdMove's 0, so the frame after a landing can jump again.
func test_a_second_jump_is_allowed_right_after_landing() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_jump()
	await step(1)
	input.release_jump()
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: the first jump never landed")
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, "the jump was refused after landing")

## [ME:CONFIRMED decompile] The pawn sweeps the box (R, R, H) square to the
## world axes: turning the body does not turn its collider.
func test_the_collider_is_a_world_aligned_box() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	assert_true(shape_node.shape is BoxShape3D, "the collider is not a box")
	assert_almost_eq((shape_node.shape as BoxShape3D).size, Vector3(0.6, 1.8, 0.6), Vector3.ONE * 0.0001)
	player.rotation.y = 0.7
	await step(1)
	assert_true(shape_node.global_basis.is_equal_approx(Basis.IDENTITY),
		"the collider turned with the body: %s" % shape_node.global_basis)
	var clearance := player.get_node("StandClearance") as Node3D
	assert_true(clearance.global_basis.is_equal_approx(Basis.IDENTITY),
		"the clearance probe turned with the body")

## [ME:CONFIRMED decompile N1 §4.1] stepUp lifts the body MaxStepHeight + 2 uu
## over anything whose face it walks into, from its 2.15 uu hover: a lip that
## only just clears the hover is climbed like any other, one past the reach
## stops the body. The low lip is the case a rounded box gets wrong -- its
## edge meets the lip at a normal that is neither wall nor floor.
func test_a_walk_steps_up_any_lip_within_the_step_and_stops_at_a_taller_one() -> void:
	for lip in [[0.03, true], [0.37, true], [0.40, false]]:
		var world: Dictionary = await _world()
		var player: Player = world["player"]
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(6.0, lip[0], 0.5)
		shape.shape = box
		body.add_child(shape)
		get_tree().root.add_child(body)
		body.global_position = Vector3(0.0, lip[0] * 0.5, -2.0)
		world["ledge"] = body
		await step(2)
		# Swept into the lip's face from the hover, the box meets a wall.
		var hover := player.global_transform
		hover.origin.y = player.collision_half_height() + PawnPhysics.FLOOR_DIST
		var hit: Dictionary = player.phys.sweep(Vector3(0.0, 0.0, -2.0), hover)
		assert_lt(absf((hit["normal"] as Vector3).y), PawnPhysics.MAX_STEP_SIDE_Z,
			"a %.0f cm lip's face is not a wall to the box: %s" % [lip[0] * 100.0, hit["normal"]])
		var input: ScriptedInputSource = world["input"]
		input.hold_move(0.0, 0.5)
		await step(150)
		var past: bool = player.global_position.z < -2.0
		assert_eq(past, lip[1], "a %.0f cm lip: the walk ended at z %.2f" % [lip[0] * 100.0,
			player.global_position.z])
		input.hold_move(0.0, 0.0)
		_free_ledge(world)
		TestWorld.teardown(world)
		_worlds.erase(world)
		await step(1)

## UE3's extent traces, whatever the box starts against: flush on a face and
## moving into it, blocked at once; inside, a hit at time 0; flush on a face
## and moving away, nothing -- and a face the box touches does not hide the
## rest of that body further along.
func test_an_extent_trace_meets_the_body_it_starts_against() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var body := StaticBody3D.new()
	for part in [[Vector3(4.0, 3.0, 2.0), Vector3(0.0, 1.5, -1.0)],
			[Vector3(4.0, 0.5, 3.0), Vector3(0.0, 3.55, -1.0)]]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[0]
		shape.shape = box
		shape.position = part[1]
		body.add_child(shape)
	get_tree().root.add_child(body)
	world["ledge"] = body
	await step(2)
	var extent := Vector3(0.3, 0.9, 0.3)
	# Flush on the wall's face at z = 0, 3 m up and clear of the floor.
	var flush := Vector3(0.0, 2.0, 0.3)
	var into: Dictionary = player.phys.box_trace(flush + Vector3(0.0, 0.0, -0.5), flush, extent)
	assert_eq(into["collider"], body, "a box flush on a face swept into it met nothing")
	assert_almost_eq(float(into["time"]), 0.0, 0.01, "a box flush on a face moved into it")
	var inside: Dictionary = player.phys.box_trace(flush + Vector3(0.0, 0.0, -0.5), flush - Vector3(0.0, 0.0, 0.1),
		extent)
	assert_eq(float(inside["time"]), 0.0, "a box starting inside did not hit at time 0")
	var away: Dictionary = player.phys.box_trace(flush + Vector3(0.0, 0.0, 0.5), flush, extent)
	assert_null(away["collider"], "a box moving off the face it touches hit it")
	var up: Dictionary = player.phys.box_trace(flush + Vector3(0.0, 2.0, 0.0), flush, extent)
	assert_eq(up["collider"], body, "the ceiling of the body the box touches was not met")
	assert_gt(float(up["time"]), 0.0, "the ceiling was met at the start")
	# Resting 2 mm into the face, as a body that slid along it is left by
	# move_actor(): still flush. Along the face it meets only the ceiling;
	# into the face, it is blocked at once.
	var resting := flush - Vector3(0.0, 0.0, 0.002)
	var along: Dictionary = player.phys.box_trace(resting + Vector3(0.0, 2.0, 0.0), resting, extent)
	assert_gt(float(along["time"]), 0.0, "a box resting in the margin of a face it slides along was inside it")
	var pressed: Dictionary = player.phys.box_trace(resting + Vector3(0.0, 0.0, -0.5), resting, extent)
	assert_eq(pressed["collider"], body, "a box resting in a face's margin swept into it met nothing")
	assert_almost_eq(float(pressed["time"]), 0.0, 0.01, "a box resting in a face's margin moved into it")
	_free_ledge(world)

## [ME:CONFIRMED decompile UStaticMeshComponent::LineCheck 0x00dbaef0] A hit
## on an extracted level mesh reaches the movement traces pulled back along
## the trace by Clamp(0.1, 0.1 / L, C / L) of its length L in uu: C = 1 uu
## by the mesh's hulls, 4 uu by its triangles. Any other body reports the
## exact contact.
func test_a_level_mesh_hit_is_pulled_back_along_the_trace() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var bodies := {}
	for kind in ["simple", "per_poly", ""]:
		var body := StaticBody3D.new()
		if kind != "":
			body.set_meta(&"me_collision", kind)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 1.0, 1.0)
		shape.shape = box
		body.add_child(shape)
		# Faces at z = 0, one body per lane along x, clear of the floor.
		body.position = Vector3(float(bodies.size()) * 3.0, 3.0, -0.5)
		get_tree().root.add_child(body)
		bodies[kind] = body
	await step(2)
	var extent := Vector3(0.05, 0.05, 0.05)
	var want := {"simple": 0.01, "per_poly": 0.04, "": 0.0}
	for kind in bodies:
		var start := Vector3((bodies[kind] as Node3D).position.x, 3.0, 2.05)
		var box_hit: Dictionary = player.traces.trace(start - Vector3(0.0, 0.0, 4.0), start, extent)
		assert_almost_eq((box_hit["location"] as Vector3).z, 0.05 + want[kind], 0.002,
			"a box sweep 4 m long met the face of a '%s' body" % kind)
		var line: Dictionary = player.traces.trace(start - Vector3(0.0, 0.0, 4.0), start)
		assert_almost_eq((line["location"] as Vector3).z, want[kind], 0.002,
			"a line 4 m long met the face of a '%s' body" % kind)
	# Under 10 uu the pull-back is a tenth of the trace: 0.5 uu of 5.
	var near := Vector3(0.0, 3.0, 0.03)
	var short: Dictionary = player.traces.trace(near - Vector3(0.0, 0.0, 0.05), near)
	assert_almost_eq((short["location"] as Vector3).z, 0.005, 0.0005, "a line 5 uu long on a hull")
	for body in bodies.values():
		(body as Node).queue_free()

## [ME:CONFIRMED decompile N1 §2.1] physWalking clears bJustTeleported on
## entry: whatever the fall before it in the same frame set, the walk rebuilds
## its velocity from the displacement -- here a wall the body ran into.
func test_the_walk_clears_just_teleported_on_entry() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	# Placed before it enters the tree: a body added at the origin and moved
	# after overlaps the player for the frame its move takes to reach the server.
	wall.position = Vector3(player.global_position.x, 1.5, player.global_position.z - (0.3 + 0.05 + 0.5))
	get_tree().root.add_child(wall)
	await step(1)
	var dt := 1.0 / 60.0
	player.velocity = Vector3(0.0, 0.0, -5.0)
	player.acceleration = Vector3(0.0, 0.0, -61.44)
	var before: Vector3 = player.global_position
	player.phys._just_teleported = true
	player.phys.phys_walking(dt, 0)
	var moved: Vector3 = player.global_position - before
	assert_almost_eq(player.velocity.z, moved.z / dt, 0.001, "the walk kept the velocity it did not travel")
	assert_lt(absf(moved.z), 0.06, "test setup: the wall did not stop the body")
	wall.queue_free()

## [ME:CONFIRMED decompile N2 §2a] Rising with the head's edge under a ceiling
## whose edge the centre is already past: the corner probes shove the body out
## from under it, and the jump carries on up past the ceiling.
func test_a_jump_under_a_ceiling_edge_is_nudged_out_from_under_it() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var slab := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 0.5, 4.0)
	shape.shape = box
	slab.add_child(shape)
	slab.position = Vector3(-2.5, 2.2 + 0.25, 0.0)
	get_tree().root.add_child(slab)
	player.global_position.x = 0.2
	await step(2)
	input.press_jump()
	var top := -INF
	for i in 40:
		await step(1)
		top = maxf(top, player.global_position.y + player.collision_half_height())
	assert_gt(player.global_position.x, 0.3, "the body was not shoved out from under the edge")
	assert_gt(top, 2.3, "the jump stopped at the ceiling")
	slab.queue_free()

## [ME:CONFIRMED decompile N1 §4.3] The corner slip that gets as far as its
## forward move scales the caller's Delta by (1 - Hit.Time) and leaves that
## move's hit in Hit; one stopped sideways puts Hit back as it came. Either way
## bJustTeleported is assigned, so a slip that does not overshoot clears it.
func test_the_corner_slip_rewrites_delta_and_hit_as_the_original() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var phys: PawnPhysics = player.phys
	var start: Vector3 = player.global_position
	var delta := Vector3(0.0, 0.0, -0.1)
	var collider := Node.new()
	var hit := {"time": 0.5, "normal": Vector3(0.0, 0.0, 1.0), "collider": collider, "position": start}
	phys._just_teleported = true
	var slip: Array = phys._corner_slip(Vector3.RIGHT, false, false, delta, hit)
	assert_true(slip[0], "an open slip did not carry the move")
	assert_almost_eq(slip[1], delta * 0.5, Vector3.ONE * 0.0001, "Delta was not scaled by 1 - Hit.Time")
	assert_almost_eq(float(hit["time"]), 1.0, 0.0001, "Hit is not the forward move's")
	assert_null(hit["collider"], "Hit is not the forward move's")
	assert_false(phys._just_teleported, "bJustTeleported was not assigned")

	player.global_position = start
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(start.x + 0.31 + 0.5, 1.5, start.z)
	get_tree().root.add_child(wall)
	await step(1)
	player.global_position = start
	hit = {"time": 0.5, "normal": Vector3(0.0, 0.0, 1.0), "collider": collider, "position": start}
	phys._just_teleported = true
	slip = phys._corner_slip(Vector3.RIGHT, false, false, delta, hit)
	assert_false(slip[0], "a slip stopped sideways carried the move")
	assert_almost_eq(slip[1], delta, Vector3.ONE * 0.0001, "a slip stopped sideways scaled Delta")
	assert_almost_eq(float(hit["time"]), 0.5, 0.0001, "Hit was not put back")
	assert_eq(hit["collider"], collider, "Hit was not put back")
	assert_false(phys._just_teleported, "bJustTeleported was not assigned")
	collider.free()
	wall.queue_free()

## [ME:CONFIRMED decompile N1 §2.1] Standing still on world geometry the walk
## reuses the floor it has instead of tracing for it -- unless the body was
## put somewhere else (RelativeLocation no longer matches) or the base stopped
## colliding (bForceFloorCheck).
func test_standing_still_reuses_the_floor_until_disturbed() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var kept := Vector3(0.1, 1.0, 0.0).normalized()
	player.floor_normal = kept
	await step(3)
	assert_eq(player.floor_normal, kept, "a still body traced for its floor")
	assert_eq(player.physics, Move.PHYS_WALKING)

	player.global_position.y += 0.5
	await step(1)
	assert_eq(player.physics, Move.PHYS_FALLING, "a body lifted off its floor kept standing on it")
	for i in 60:
		await step(1)
		if player.physics == Move.PHYS_WALKING:
			break
	await step(3)
	assert_eq(player.physics, Move.PHYS_WALKING, "test setup: the body never landed again")

	var floor_shape := (world["floor"] as Node).get_child(0) as CollisionShape3D
	floor_shape.disabled = true
	await step(2)
	assert_eq(player.physics, Move.PHYS_FALLING, "a body kept standing on a floor that stopped colliding")
	floor_shape.disabled = false

## bForceFloorCheck also covers the base going away: a floor freed under a
## still body is no floor.
func test_standing_still_on_a_floor_that_is_freed_falls() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	assert_eq(player.physics, Move.PHYS_WALKING, "test setup: the body is not standing")
	var floor_body: Node = world["floor"]
	world.erase("floor")
	floor_body.free()
	await step(2)
	assert_eq(player.physics, Move.PHYS_FALLING, "a body kept standing on a floor that was freed")
	world["floor"] = Node3D.new()

## A body that lands on geometry the physics server still has where a node
## has just left must not keep standing on it: the node's new position cannot
## show the carry what the trace saw, so the landing itself raises the
## floor check.
func test_a_landing_on_geometry_moved_this_frame_does_not_keep_the_floor() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var pad := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.0, 4.0)
	shape.shape = box
	pad.add_child(shape)
	get_tree().root.add_child(pad)
	pad.global_position = Vector3(20.0, 1.5, 0.0)
	await step(3)
	player.global_position = Vector3(20.0, 3.0, 0.0)
	pad.global_position = Vector3(20.0, 100.0, 0.0)
	await step(90)
	assert_eq(player.physics, Move.PHYS_WALKING, "the body never came to rest")
	assert_lt(player.global_position.y, 1.2, "the body stands in the air on a floor that left")
	pad.free()

## [ME:CONFIRMED decompile N4 §1.1] The input ignores are the pawn's Actor
## timers, counted after the controller has read the frame's input: an ignore
## that runs out in a frame still held that frame.
func test_an_input_ignore_holds_the_frame_it_runs_out_in() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(2)
	player.set_ignore_move_input(1.5 / 60.0)
	await step(1)
	assert_eq(player.a_forward, 0.0, "the ignored frame read the input")
	await step(1)
	assert_eq(player.a_forward, 0.0, "the frame the ignore ran out in read the input")
	await step(1)
	assert_gt(player.a_forward, 0.0, "the ignore outlived its time")

## [ME:CONFIRMED decompile] bLeftThumbStickPassedDeadZone starts true: a
## stick already pushed on the first frame gives its hint without first going
## back through the dead zone.
func test_a_stick_pushed_from_the_start_gives_its_hint() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	var player: Player = world["player"]
	(world["input"] as ScriptedInputSource).hold_move(0.0, 1.0)
	# A few frames: the stick never goes back through the dead zone, so a
	# flag that started false would still be withholding the hint.
	await step(3)
	assert_eq(player.move_action_hint, Move.MAH_UP)

## [ME:CONFIRMED decompile 15.2] The turn penalty's aTurn is the frame's raw
## yaw input in rotator units, nothing the view did with it -- and zero while
## look input is ignored.
func test_the_turn_penalty_reads_the_raw_yaw_input() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.look = Vector2(40.0, 0.0)
	await step(1)
	assert_eq(player.turn_units,
		PawnAcceleration.turn_units(-40.0 * player.config.camera.mouse_sensitivity))
	player.set_ignore_look_input(-1.0)
	await step(1)
	assert_eq(player.turn_units, 0, "an ignored look still billed a turn")
	player.stop_ignore_look_input()
	input.state.look = Vector2.ZERO

## A ported move whose automatic transitions hand the body to a move not yet
## ported, and that move, counting its physics updates.
class HandsOver extends WalkingMove:
	func check_auto_moves() -> void:
		player.move_manager.set_move(&"TestUnported")

class Unported extends Move:
	var updates := 0
	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		updates += 1
		player.set_grounded(true)
		return KEEP

## [ME:CONFIRMED decompile N4 §1.1] The physics runs after the automatic
## transitions whatever they chose: a hand-over from CheckAutoMoves to a move
## not yet ported still moves the body that frame, through that move's own
## physics.
func test_an_automatic_hand_over_still_runs_the_frames_physics() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var manager: MoveManager = player.move_manager
	var unported := Unported.new()
	var hands_over := HandsOver.new()
	for entry in [[&"TestUnported", unported], [&"TestHandsOver", hands_over]]:
		var move: Move = entry[1]
		move.player = player
		move.config = player.config
		move.cfg = player.config.walking
		manager.add_child(move)
		manager.register(entry[0], move)
	manager.start(&"TestHandsOver")
	await step(1)
	assert_eq(manager.current_name, &"TestUnported", "test setup: the hand-over did not happen")
	assert_eq(unported.updates, 1, "the frame of the hand-over ran no physics")
	manager.start(Move.WALKING)

## [ME:CONFIRMED decompile 15.4] The forced Walking frame runs
## Walking.StartMove, which clears the wall-run jump's ledge ban.
func test_walking_start_clears_the_illegal_ledge_timer() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_jump()
	await step(5)
	player.illegal_ledge_timer = 2.0
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.illegal_ledge_timer, 0.0, "landing into Walking left the ledge ban running")

## [ME:CONFIRMED decompile N4 §1.2] A SetMove with bCheckCanDo that fails
## still writes PendingMovementState, and while it differs from the move
## TdPawn.CanDoMove refuses everything. The next successful SetMove ends it.
func test_a_refused_checked_set_move_leaves_pending_behind() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var manager: MoveManager = player.move_manager
	var falling: Move = manager.move_for(Move.FALLING)
	falling.last_stop_move_time = player.world_time
	falling.cfg.redo_move_time = 10.0
	assert_false(manager.set_move(Move.FALLING, true), "a cooling-down Falling was set")
	assert_eq(manager.current_name, Move.WALKING)
	assert_eq(player.pending_movement_state, Move.FALLING)
	assert_false(manager.pawn_can_do(Move.JUMP), "CanDoMove answered with a stale Pending")
	assert_true(manager.set_move(Move.JUMP))
	assert_eq(player.pending_movement_state, Move.JUMP)
	falling.cfg.redo_move_time = 0.0

## [ME:CONFIRMED decompile] A level's knock-down (TdPlayerPawn.OnTdFallOnBack)
## asks TdPawn.CanDoMove, so a stale PendingMovementState refuses it.
func test_a_stale_pending_refuses_a_knock_down() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var manager: MoveManager = player.move_manager
	var falling: Move = manager.move_for(Move.FALLING)
	falling.last_stop_move_time = player.world_time
	falling.cfg.redo_move_time = 10.0
	assert_false(manager.set_move(Move.FALLING, true), "test setup: a cooling-down Falling was set")
	falling.cfg.redo_move_time = 0.0
	var down := StatusSpec.new()
	down.effect = Status.Effect.KNOCKDOWN
	down.seconds = 0.5
	player.apply_status(down, self, 0, true)
	await step(1)
	assert_eq(manager.current_name, Move.WALKING, "a knock-down went through a stale Pending")
	manager.set_move(Move.JUMP)
	await step(1)
	assert_eq(manager.current_name, Move.LAY_ON_GROUND, "the knock-down was refused after a successful SetMove")

## [ME:CONFIRMED decompile N1 §2.1] No walkable floor: the walking physics sets
## Falling, then SetMove(Falling, check) -- and the fall height starts at the
## edge.
func test_walking_off_an_edge_sets_falling_physics_and_move() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	_ledge(world, 3.0)
	player.global_position = Vector3(0.0, 3.0 + 0.95, -1.0)
	player.rotation.y = PI
	await step(10)
	input.hold_move(0.0, 1.0)
	var height_at_edge: float = player.global_position.y
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
	assert_eq(player.move_manager.current_name, Move.FALLING)
	assert_eq(player.physics, Move.PHYS_FALLING)
	assert_almost_eq(player.enter_falling_height, height_at_edge, 0.02)
	_free_ledge(world)

## [ME:CONFIRMED decompile 15.4] Falling.StartMove after Walking: a body
## moving backwards with a body height of room below drops straight down.
func test_backing_off_an_edge_drops_straight_down() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	_ledge(world, 3.0)
	player.global_position = Vector3(0.0, 3.0 + 0.95, -1.0)
	await step(10)
	input.hold_move(0.0, -1.0)
	var walking_speed: float = 0.0
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.FALLING:
			break
		walking_speed = player.horizontal_speed()
	assert_eq(player.move_manager.current_name, Move.FALLING)
	assert_gt(walking_speed, 3.0, "test setup: not walking backwards")
	assert_lt(player.horizontal_speed(), 0.5, "backing off the edge kept its speed")
	_free_ledge(world)

## [ME:CONFIRMED decompile 15.6] After a jump's fall the landing caps the
## horizontal speed at PreJumpMomentum - 65 uu/s. Read as Landing hands on:
## the walking physics then runs the rest of the touchdown frame on it.
func test_a_jumps_landing_caps_the_speed_at_its_take_off_speed() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(90)
	input.press_jump()
	await step(1)
	input.hold_move(0.0, 0.0)
	var jump: Move = player.move_manager.move_for(Move.JUMP)
	var airborne_speed: float = player.horizontal_speed()
	var at_landing := [-1.0]
	player.move_manager.move_changed.connect(func(_from: StringName, to: StringName) -> void:
		if to == Move.LANDING:
			at_landing[0] = player.horizontal_speed())
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.move_manager.move_for(Move.FALLING).previous_move, Move.JUMP)
	assert_gt(airborne_speed, jump.pre_jump_momentum, "test setup: the jump took no nudge")
	assert_almost_eq(float(at_landing[0]), jump.pre_jump_momentum - 0.65, 0.001, \
		"the landing speed is not PreJumpMomentum - LandingSpeedReduction")

## [ME:CONFIRMED decompile] Landing.StartMove sets SkillRoll without asking
## its CanDoMove: a roll the move itself would refuse (here, cooling down)
## still happens.
func test_a_rolled_landing_does_not_ask_the_roll_first() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	player.global_position.y += 3.0
	player.move_manager.start(Move.FALLING)
	player.move_manager._redo_cooldowns[Move.SKILL_ROLL] = 10.0
	assert_false(player.move_manager.can_do(Move.SKILL_ROLL), "test setup: the roll is not refused")
	var pressed := false
	for i in 120:
		if not pressed and player.velocity.y < 0.0 and player.global_position.y < 1.6:
			input.press_crouch()
			pressed = true
		await step(1)
		if player.move_manager.current_name == Move.SKILL_ROLL:
			break
	assert_eq(player.move_manager.current_name, Move.SKILL_ROLL)

## [ME:CONFIRMED decompile 15.6] A hard landing holds the body with move and
## look input ignored until it ends, then sets Walking.
func test_a_hard_landing_holds_the_body_with_input_ignored() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.global_position.y += player.config.pawn.hard_landing_height + 1.0
	player.move_manager.start(Move.FALLING)
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	var landing: Move = player.move_manager.move_for(Move.LANDING)
	assert_eq(player.move_manager.current_name, Move.LANDING)
	assert_eq(landing.kind, LandingMove.Kind.HARD)
	assert_true(player.ignore_move_input and player.ignore_look_input)
	await step(int(player.config.landing.lockout_time * 60.0) + 2)
	assert_eq(player.move_manager.current_name, Move.WALKING)
	assert_false(player.ignore_move_input or player.ignore_look_input, "the hold outlived Landing")

## [ME:CONFIRMED decompile 15.3] Walking + jump asks DodgeJump first: a full
## strafe (the hint at its maximum) is a dodge, forward is a jump.
func test_walking_jump_asks_dodge_jump_before_jump() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(-1.0, 0.0)
	await step(3)
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP)

## [ME:CONFIRMED decompile 15.2] PlayerWalking's tap: input released inside
## 0.15 s stops the body at 35 uu/s for 0.25 s.
func test_a_tap_stops_the_body_at_35_uu_per_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(5)
	input.hold_move(0.0, 0.0)
	await step(3)
	assert_almost_eq(player.horizontal_speed(), 0.35, 0.02, "the tap did not stop at 35 uu/s")

## [ME:CONFIRMED emulated 15.2, N1 §3] The sprint from rest follows the
## SpeedCurve the acceleration curve is built from: 520 uu/s at 1 s, 720 uu/s
## at 7 s, give or take what the friction the acceleration adds back leaves
## over.
func test_a_sprint_from_rest_follows_the_speed_curve() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(60)
	assert_almost_eq(player.horizontal_speed(), 5.2, 0.15, "speed after 1 s of sprinting")
	await step(360)
	assert_almost_eq(player.horizontal_speed(), 7.2, 0.15, "speed after 7 s of sprinting")

## [ME:CONFIRMED decompile] TdPlayerController.LookBehind returns before
## HandleMoveAction(MA_Turn) in a move at MG_NonInteractive.
func test_q_does_nothing_in_a_non_interactive_move() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	for name in [Move.BARGE, Move.AIR_BARGE, Move.MELEE, Move.MELEE_AIR, Move.MELEE_SLIDE,
			Move.MELEE_CROUCH, Move.MELEE_WALLRUN, Move.GRAB_PULL_UP, Move.INTERACT,
			Move.INTO_CLIMB, Move.INTO_GRAB, Move.INTO_ZIPLINE]:
		var move: Move = player.move_manager.move_for(name)
		if move != null:
			assert_eq(move.movement_group, Move.MG_NON_INTERACTIVE, "%s is not MG_NonInteractive" % name)
	assert_eq(player.move_manager.move_for(Move.MELEE_VAULT).movement_group, Move.MG_ONE_HAND_BUSY,
		"MeleeVault kept its base's group")
	player.move_manager.start(Move.MELEE)
	var serial: int = player.move_manager.change_serial
	assert_true(player._look_behind(), "a refused Q was left over for a move not yet ported")
	assert_eq(player.move_manager.change_serial, serial, "Q changed a non-interactive move")

## [ME:CONFIRMED decompile TdPawn.TakeDamage, TdMove_*.HandleDeath] A blow
## that would kill is the current move's to answer: a pull-up survives it with
## one point; a wall run lets go into Falling and dies.
func test_a_killing_blow_asks_the_move_first() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var pull_up: Move = player.move_manager.move_for(Move.GRAB_PULL_UP)
	assert_almost_eq(pull_up.handle_death(500.0), player.health.hp - 1.0, 0.0001,
		"the pull-up did not keep one point")
	player.global_position.y += 3.0
	player.move_manager.start(Move.WALL_RUN)
	player.take_damage(player.health.hp + 50.0, Health.Cause.HAZARD)
	assert_eq(player.move_manager.current_name, Move.FALLING, "the wall run did not let go")
	assert_true(player.health.is_dead(), "the blow did not kill")
