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

## wall_min_speed's own doc comment says wall running is "a way to CARRY
## speed, never a way to create it from nothing" -- if wall_max_speed exceeded
## what foot speed alone can reach, the wall's own accel would top the player
## up past sprint or air control, creating speed no other move can, which
## directly contradicts that comment and the spec's "speed is hard to earn,
## easy to lose". Pinned against BOTH ceilings a player can otherwise reach,
## since either one alone could rise past the wall's cap under future tuning.
## camera_head_follow_strength is a lerp weight -- meaningless outside
## [0, 1] -- and its own doc comment commits to defaulting LOW so an owner
## dials UP from a stable camera rather than DOWN from a nauseating one.
## "Low" is checked as "in the bottom half of the valid range", not a bare
## value pin, so this survives a future retune that keeps the design intent
## but nudges the exact number.
func test_camera_head_follow_strength_defaults_low_and_in_range() -> void:
	await step(1)
	var c := MovementConfig.new()
	check(c.camera_head_follow_strength >= 0.0, "camera_head_follow_strength must not default negative")
	check(c.camera_head_follow_strength <= 1.0, "camera_head_follow_strength must not default above 1.0")
	check(c.camera_head_follow_strength < 0.5, \
		"camera_head_follow_strength (%f) must default low, in the bottom half of [0, 1]" \
			% c.camera_head_follow_strength)

func test_wall_running_cannot_create_speed_beyond_what_foot_speed_reaches() -> void:
	await step(1)
	var c := MovementConfig.new()
	check(c.wall_max_speed <= c.sprint_speed, \
		"wall_max_speed (%f) exceeds sprint_speed (%f) -- the wall creates speed sprinting never could" \
			% [c.wall_max_speed, c.sprint_speed])
	check(c.wall_max_speed <= c.air_max_speed, \
		"wall_max_speed (%f) exceeds air_max_speed (%f) -- the wall creates speed air control never could" \
			% [c.wall_max_speed, c.air_max_speed])
