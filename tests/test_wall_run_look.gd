extends ParkourTest

# What the view does during a wall run, and -- more importantly -- what it does
# NOT do to the run.
#
# All three of these come from one correction by the owner:
#
#   "Wall running actually has a 90 degree look clamp -- running the left wall,
#    you can only look to the right-front. And the view during a run does not
#    affect the run: the character always hugs the wall and completes the
#    wall-run curve. (Right now you fall off the moment you stop looking
#    forward.) Space during a run jumps toward the view, so turning 90 degrees
#    right by hand and pressing space should feel the same as Q and space."

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	if _world.has("wall"):
		(_world["wall"] as Node).queue_free()
	for piece in _curve_pieces:
		# free(), not queue_free(): a curve is a dozen static bodies, and two
		# tests' worth left pending until the end of the frame was enough to
		# make Jolt complain about its job pool and fail an unrelated suite.
		piece.get_parent().remove_child(piece)
		piece.free()
	_curve_pieces.clear()
	TestWorld.teardown(_world)
	_world = {}

## The same fixture tests/test_wall_run_entry.gd uses: a wall to the player's
## RIGHT, entered by running along -Z beside it.
func _running_the_wall() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	world["wall"] = wall
	wall.global_position = Vector3(0.95, 3.0, 0.0)
	wall.rotation = Vector3(0.0, PI * 0.5, 0.0)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(30)
	input.press_jump()
	await step(1)
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the wall")
	return player

# --- the run does not care where you look ------------------------------------

func test_turning_the_view_does_not_end_the_run() -> void:
	# THE BUG. wall_query()'s rays are rigidly local, so turning the view swung
	# them off the wall, the query came back invalid, and the run ended. A run
	# now tracks the wall by the normal it already knows.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	# A hard swing, spread over several ticks the way a real hand would deliver
	# it. AWAY from the wall, which is the direction the fan allows: this
	# fixture's wall is on the right, so away is leftward, which is mouse-left,
	# which is a negative look.x.
	for i in 8:
		input.state.look = Vector2(-60.0, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"looking away from the wall dropped the player off it")

func test_the_run_still_hugs_the_wall_after_a_look() -> void:
	# Not merely "still in the state": the body has to still be ON the wall.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	var distance_before: float = absf(player.global_position.x - 0.45)
	for i in 8:
		input.state.look = Vector2(-60.0, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	var distance_after: float = absf(player.global_position.x - 0.45)
	assert_lt(distance_after, distance_before + 0.25, \
		"the body drifted off the wall while the view turned (%.2f -> %.2f)" \
		% [distance_before, distance_after])

# --- the fan is one-sided ----------------------------------------------------

func test_the_yaw_fan_is_a_quarter_turn_away_from_the_wall() -> void:
	# The CDO's own +-90 is symmetric, a half-circle in total. What reaches the
	# player is half of that, on the away side -- which is also what makes sense
	# of the original shipping a WallRunLeft and a WallRunRight whose only
	# difference is the mirroring.
	# THE SIGN IS THE WHOLE TEST. Yaw grows counter-clockwise seen from above,
	# which is leftward, so the fan a LEFT-hand wall gets -- the one declared --
	# is the NEGATIVE half, because a left wall is the one the view turns away
	# from to the RIGHT. Declared the other way round, as it was on its first
	# outing, the clamp pins the view INTO the wall.
	var config := MovementConfig.new()
	assert_almost_eq(config.wall_run.max_look_constraint.y, 0.0, 0.001, \
		"the fan reaches past straight-ahead, into the wall")
	assert_almost_eq(config.wall_run.min_look_constraint.y, -deg_to_rad(90.0), 0.001, \
		"the fan is not a quarter turn wide, on the away side")
	assert_true(config.wall_run.mirror_yaw_by_wall_side, \
		"the fan is one-sided but never mirrored, so one of the two walls is wrong")

func test_the_view_cannot_be_turned_into_the_wall() -> void:
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	assert_eq(player.wall_side, 1, "test setup is wrong: the wall is not on the right")
	# INTO the wall, hard and repeatedly. The wall is on the right, so that is
	# mouse-right, a positive look.x.
	for i in 8:
		input.state.look = Vector2(60.0, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	var fan: Dictionary = player.camera_rig.look_debug()
	# Mirrored for a right-hand wall the legal range is [0, +90], so turning
	# into the wall is refused at 0.
	assert_gt(float(fan["relative_yaw"]), -0.001, \
		"the view turned into the wall (%.1f degrees)" % rad_to_deg(float(fan["relative_yaw"])))

# --- Q ------------------------------------------------------------------------

func test_q_sweeps_the_view_and_leaves_the_body_alone() -> void:
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	var speed_before: float = player.horizontal_speed()
	input.press_turn()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"Q pulled the player out of the wall run")
	assert_gt(player.horizontal_speed(), speed_before * 0.5, \
		"Q pinned the character in place instead of only moving the view")

func test_q_carries_the_view_to_the_far_edge_of_the_fan() -> void:
	# The far edge IS the direction a kick should leave in, which is why Q and
	# space read the same as turning by hand and pressing space.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	input.press_turn()
	# look_sweep_speed is the measured 5.24 rad/s, so a quarter turn is 18 ticks.
	await step(25)
	var fan: Dictionary = player.camera_rig.look_debug()
	# The wall is on the right, so away is leftward, which is positive yaw.
	assert_almost_eq(float(fan["relative_yaw"]), deg_to_rad(90.0), 0.05, \
		"the sweep did not reach the fan's away edge (%.1f degrees)" \
		% rad_to_deg(float(fan["relative_yaw"])))

func test_the_mouse_takes_the_sweep_back() -> void:
	# A convenience that resists being overridden is worse than none.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	input.press_turn()
	await step(3)
	var caught: float = float(player.camera_rig.look_debug()["relative_yaw"])
	input.state.look = Vector2(-5.0, 0.0)
	await step(1)
	input.state.look = Vector2.ZERO
	assert_false(player.camera_rig.is_sweeping(), "the mouse did not cancel the sweep")
	await step(20)
	assert_lt(absf(float(player.camera_rig.look_debug()["relative_yaw"]) - caught), 0.3, \
		"the sweep carried on after the player took the mouse back")

# --- the fan belongs to the wall ---------------------------------------------

func test_the_fan_is_centred_on_the_wall_not_on_the_approach() -> void:
	# The same mistake the ledge hang made first: leaving the fan where
	# set_look_constraint captured it centres it on whatever the body happened
	# to be facing on attach. The forward branch admits approaches up to 57
	# degrees off the wall's line, so "look 90 degrees away" would mean
	# something different on every attach.
	#
	# Approached at an angle deliberately: the body is turned 25 degrees toward
	# the wall before the attach, so a fan centred on the approach and a fan
	# centred on the wall are 25 degrees apart and the assertion can tell them
	# apart.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	world["wall"] = wall
	wall.global_position = Vector3(0.95, 3.0, 0.0)
	wall.rotation = Vector3(0.0, PI * 0.5, 0.0)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(30)
	input.press_jump()
	await step(1)
	# Facing skewed toward the wall, travelling along it. The run's own line is
	# -Z; the body is looking 25 degrees off that.
	player.rotation.y = -deg_to_rad(25.0)
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the wall")

	# THE SKEW ITSELF IS THE PROOF. The wall is on the right, so the legal fan is
	# [0, +90] and a view 25 degrees INTO the wall is outside it. Reading -25
	# means the fan is measured from the wall's own line and the view is where
	# the player actually left it; reading a comfortable 0 would mean the fan
	# had quietly moved to accommodate the approach, which is the bug.
	var early: float = float(player.camera_rig.look_debug()["relative_yaw"])
	assert_lt(early, -deg_to_rad(15.0), \
		"the fan followed the approach instead of the wall (%.1f degrees)" \
		% rad_to_deg(early))

	# ...and then the fan's edge eases in to collect it, rather than the view
	# being cut to the edge on the first tick. Both halves matter: the first
	# assertion alone would pass a version that never corrected at all.
	await step(30)
	var late: float = float(player.camera_rig.look_debug()["relative_yaw"])
	assert_gt(late, -deg_to_rad(2.0), \
		"the view never settled into the fan (%.1f degrees)" % rad_to_deg(late))
	assert_lt(late, deg_to_rad(91.0), "the view left the fan entirely")

func test_the_view_is_carried_into_the_fan_rather_than_cut_to_it() -> void:
	# The owner asked for this directly: "can the yaw get some smoothing when
	# entering a wall run? The pitch seems fine as it is."
	#
	# Measured as a RATE rather than an endpoint -- an implementation that cuts
	# and one that eases both end up inside the fan, and only how they got there
	# tells them apart.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	world["wall"] = wall
	wall.global_position = Vector3(0.95, 3.0, 0.0)
	wall.rotation = Vector3(0.0, PI * 0.5, 0.0)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(30)
	input.press_jump()
	await step(1)
	player.rotation.y = -deg_to_rad(25.0)
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the wall")

	var before: float = float(player.camera_rig.look_debug()["relative_yaw"])
	await step(1)
	var after: float = float(player.camera_rig.look_debug()["relative_yaw"])
	assert_gt(after, before, "the correction did not move at all")
	assert_lt(after - before, deg_to_rad(12.0), \
		"the view was cut into the fan in one tick (%.1f degrees of correction)" \
		% rad_to_deg(after - before))

# --- curved walls -------------------------------------------------------------

## A wall built from `count` straight segments laid along an arc, each turned a
## few degrees from the last -- a blockout's version of a continuous curve, and
## what the owner meant by "a small-angle continuous surface".
##
## The arc is CONCAVE toward the player: its centre lies on the player's side,
## so the surface wraps around the run rather than falling away from it.
func _curved_wall(count: int, radius: float, segment: float) -> void:
	var centre := Vector3(0.45 - radius, 3.0, 0.0)
	for i in count:
		var theta: float = (float(i) + 0.5) * segment / radius
		var out := Vector3(cos(theta), 0.0, -sin(theta))
		var piece := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Long axis along local Z, one metre thick, tall enough not to be a ledge.
		box.size = Vector3(1.0, 6.0, segment * 1.15)
		shape.shape = box
		piece.add_child(shape)
		get_tree().root.add_child(piece)
		piece.global_position = centre + out * (radius + 0.5)
		piece.rotation = Vector3(0.0, PI + theta, 0.0)
		_curve_pieces.append(piece)

var _curve_pieces: Array[Node] = []

func test_a_gently_curving_wall_can_be_run_all_the_way_along() -> void:
	# NOT DESIGNED, but real, and the owner confirmed the original does it: "you
	# really can run along an inward-curving arc." It falls out of two decisions
	# that were made for other reasons -- _derive_along() recomputing the
	# tangent from the CURRENT normal every tick, and wall_tracked_query()
	# following the wall by that normal rather than by the body's sides.
	#
	# Pinned here so neither can be quietly undone. Caching the tangent at
	# attach would look like a harmless tidy-up and would flatten every curve in
	# the game back into a straight line.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	_curved_wall(6, 25.0, 3.0)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(30)
	input.press_jump()
	await step(1)
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the curve")

	# Far enough along that the surface has genuinely turned: 10 segments of 2 m
	# on a 25 m radius is about 45 degrees end to end.
	var heading_at_start := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	var ticks := 0
	while ticks < 40 and player.move_manager.current_name == Move.WALL_RUN:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"the run came off the curve after %d ticks" % ticks)
	var heading_now := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	assert_gt(rad_to_deg(heading_at_start.angle_to(heading_now)), 3.0, \
		"the run did not follow the curve at all -- it went straight")

func test_the_fan_travels_round_the_curve_with_the_wall() -> void:
	# The clamp is measured against the wall's own line, so on a curve it has to
	# turn with it. Left where it was captured, it ends up policing a direction
	# the wall stopped pointing in metres ago -- the player runs happily along a
	# curve while the fan quietly rotates out from under them.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	_curved_wall(6, 25.0, 3.0)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	await step(1)
	TestWorld.place(world)
	await step(30)
	input.press_jump()
	await step(1)
	player.velocity = Vector3(0.0, player.velocity.y, -7.0)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the curve")

	# Looking straight along the run and holding still. If the fan follows the
	# wall, "straight along" stays near the fan's centre the whole way round; if
	# it does not, the reading drifts by however far the wall turned.
	var reading_early: float = float(player.camera_rig.look_debug()["relative_yaw"])
	var ticks := 0
	while ticks < 40 and player.move_manager.current_name == Move.WALL_RUN:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"the run came off the curve after %d ticks" % ticks)
	var reading_late: float = float(player.camera_rig.look_debug()["relative_yaw"])
	assert_lt(absf(reading_late - reading_early), deg_to_rad(20.0), \
		"the fan did not travel with the wall (%.1f -> %.1f degrees)" \
		% [rad_to_deg(reading_early), rad_to_deg(reading_late)])

func test_the_view_is_only_assisted_round_the_curve_not_locked_to_it() -> void:
	# An ASSIST, in the owner's own word. The clamp travels the full turn; the
	# view is carried part of the way, so the run guides the eyes rather than
	# steering them. Locked at 1.0 this is indistinguishable from the game
	# taking the mouse away.
	var config := MovementConfig.new()
	assert_gt(config.wall_run.view_assist, 0.0, "the view is not carried at all")
	assert_lt(config.wall_run.view_assist, 1.0, "the view is locked to the wall")

func test_a_sweep_does_not_outlive_the_run_that_started_it() -> void:
	# Reported in play: pressing Q just as a wall run ends spins the player on
	# the spot indefinitely.
	#
	# A sweep is expressed in the FAN's coordinates. Once the run ends the fan
	# goes with it, and apply_look falls back to rotating the body directly
	# without ever updating the running total the sweep measures against -- so
	# the distance left to travel never shrinks and the sweep never finishes.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	input.press_turn()
	await step(2)
	assert_true(player.camera_rig.is_sweeping(), "the sweep never started")
	# End the run the way play does -- there is no wall left to track.
	(_world["wall"] as Node3D).global_position = Vector3(500.0, 0.0, 0.0)
	await step(3)
	assert_ne(player.move_manager.current_name, Move.WALL_RUN, \
		"test setup is wrong: the run did not end")
	assert_false(player.camera_rig.is_sweeping(), \
		"the sweep survived the run and is still turning the player")

	var facing_before := player.rotation.y
	await step(20)
	assert_almost_eq(wrapf(player.rotation.y - facing_before, -PI, PI), 0.0, 0.01, \
		"the player kept turning after the run ended (%.1f degrees)" \
		% rad_to_deg(wrapf(player.rotation.y - facing_before, -PI, PI)))

func test_q_then_space_carries_the_measured_distance() -> void:
	# ✅ MEASURED in the original: from a near-perfect high point on a wall run,
	# Q and then space carries Faith from X 208.2 to X 214.7 -- 6.5 m sideways
	# off the wall.
	#
	# A whole-manoeuvre figure, deliberately: it is the product of the sweep's
	# speed, the fan's width, how much of the run's speed the kick turns, and
	# the push on top. Any of those drifting shows up here, and none of them can
	# be checked against the original on its own.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	# Pressed early rather than at the very top of the arc. Waiting for the rise
	# to top out AND THEN sweeping for 0.3 s spends more of the run than this
	# fixture's wall has left in it -- a finding in its own right, recorded in
	# docs/feel-backlog.md rather than papered over here.
	input.press_turn()
	# The measured sweep is a little under 0.3 s, which is 18 ticks.
	await step(18)
	var launched_from := player.global_position
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"the kick never left the wall")
	var ticks := 0
	while ticks < 300 and not player.grounded:
		await step(1)
		ticks += 1
	var travelled: float = Vector2(player.global_position.x - launched_from.x,
		player.global_position.z - launched_from.z).length()
	# A wide band on purpose. The original's figure came off a specific spot in
	# a specific level, and this fixture is a bare wall over flat ground; what
	# is being pinned is the ORDER of the distance, not the decimal.
	assert_gt(travelled, 4.0, \
		"a Q-and-kick carried only %.1f m, against the original's 6.5" % travelled)
	assert_lt(travelled, 10.0, \
		"a Q-and-kick carried %.1f m, well past the original's 6.5" % travelled)
	print("[measure] Q + kick carried %.2f m (original: 6.5 m)" % travelled)

func test_space_during_the_sweep_waits_for_the_view_to_arrive() -> void:
	# ✅ THE ORIGINAL PRE-BUFFERS THIS, and the owner names both cases: a wall
	# climb's turn and a wall run's jump. The kick steers by the view, so taking
	# it mid-sweep launches along a facing halfway to the one the player asked
	# for -- and asking for that facing is the entire reason to press Q.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	input.press_turn()
	await step(3)
	assert_true(player.camera_rig.is_sweeping(), "the sweep never started")
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, \
		"the kick fired mid-sweep instead of waiting for the view")
	# Held, not dropped: the sweep finishes and the press is spent on the tick
	# it does.
	var ticks := 0
	while ticks < 30 and player.move_manager.current_name == Move.WALL_RUN:
		await step(1)
		ticks += 1
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"the held press was never spent once the sweep finished")

func test_space_without_a_sweep_kicks_immediately() -> void:
	# Only a SWEEP defers the kick. A player who never pressed Q is asking to
	# leave now, and waiting on nothing would be a delay with no cause.
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"a kick with no sweep running was made to wait")
