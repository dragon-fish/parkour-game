class_name GroundState
extends PlayerState

func enter(_previous: StringName) -> void:
	player.velocity.y = 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	var target_speed: float = config.sprint_speed if input.sprint_held else config.walk_speed
	player.ground_accelerate(wish_dir, target_speed, delta)

	if player.consume_jump():
		player.velocity.y = config.jump_velocity
		player.move_and_slide()
		return AIR

	# A small downward bias keeps the body glued to the floor across seams and
	# gentle slopes; without it is_on_floor() flickers while running.
	player.velocity.y = -2.0
	player.move_and_slide()

	if not player.is_on_floor():
		return AIR
	return KEEP
