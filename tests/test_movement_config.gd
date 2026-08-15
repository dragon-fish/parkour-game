extends TestCase

# These assert relationships between parameters, never their values, so they
# survive tuning. If a relationship here breaks, the feel is broken too.

func test_sprint_is_faster_than_walk() -> void:
	await step(1)
	var c := MovementConfig.new()
	check_greater(c.sprint_speed, c.walk_speed, "sprint must be faster than walk")

func test_air_control_is_weaker_than_ground_control() -> void:
	await step(1)
	var c := MovementConfig.new()
	# The whole "commit to your jump" feel depends on this ordering.
	check_greater(c.ground_accel, c.air_accel, "ground acceleration must exceed air acceleration")

func test_fov_widens_with_speed() -> void:
	await step(1)
	var c := MovementConfig.new()
	check_greater(c.fov_max, c.fov_base, "max FOV must exceed base FOV")

func test_terminal_velocity_exceeds_jump_velocity() -> void:
	await step(1)
	var c := MovementConfig.new()
	check_greater(c.terminal_velocity, c.jump_velocity, "terminal velocity must exceed jump velocity")
