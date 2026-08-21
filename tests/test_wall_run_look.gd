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
	# it. Away from the wall, which is the direction the fan allows.
	for i in 8:
		input.state.look = Vector2(60.0, 0.0)
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
		input.state.look = Vector2(60.0, 0.0)
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
	var config := MovementConfig.new()
	assert_almost_eq(config.wall_run.min_look_constraint.y, 0.0, 0.001, \
		"the fan reaches back past straight-ahead, into the wall")
	assert_almost_eq(config.wall_run.max_look_constraint.y, deg_to_rad(90.0), 0.001, \
		"the fan is not a quarter turn wide")
	assert_true(config.wall_run.mirror_yaw_by_wall_side, \
		"the fan is one-sided but never mirrored, so one of the two walls is wrong")

func test_the_view_cannot_be_turned_into_the_wall() -> void:
	var player: Player = await _running_the_wall()
	var input: ScriptedInputSource = _world["input"]
	assert_eq(player.wall_side, 1, "test setup is wrong: the wall is not on the right")
	# Toward the wall, hard and repeatedly.
	for i in 8:
		input.state.look = Vector2(-60.0, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	var fan: Dictionary = player.camera_rig.look_debug()
	# Mirrored for a right-hand wall, the legal range is [-90, 0]: turning INTO
	# the wall is the positive direction and must be refused at 0.
	assert_lt(float(fan["relative_yaw"]), 0.001, \
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
	# look_sweep_speed is 6 rad/s, so a quarter turn takes about 16 ticks.
	await step(25)
	var fan: Dictionary = player.camera_rig.look_debug()
	assert_almost_eq(float(fan["relative_yaw"]), -deg_to_rad(90.0), 0.05, \
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
