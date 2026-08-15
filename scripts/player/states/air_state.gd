class_name AirState
extends PlayerState

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	player.air_accelerate(wish_dir, delta)

	# Coyote time: Player.consume_jump() already gates on the timer, so a jump
	# buffered just after walking off a ledge still fires here.
	if player.consume_jump():
		player.velocity.y = config.jump_velocity

	player.velocity.y -= config.gravity * delta
	player.velocity.y = maxf(player.velocity.y, -config.terminal_velocity)

	# Capture the impact speed before move_and_slide() zeroes it on contact.
	var impact_speed := maxf(-player.velocity.y, 0.0)
	player.move_and_slide()

	if player.is_on_floor():
		player.last_landing_speed = impact_speed
		return GROUND
	return KEEP
