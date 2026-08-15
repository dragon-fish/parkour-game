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

	# A slide has to be earned: crouching below the entry speed just crouches.
	# Gated on a fresh press (not crouch_held) so holding crouch while running
	# cannot immediately re-enter Slide the instant a slide ends — that would
	# strobe Slide<->Ground every couple of frames instead of committing.
	if input.crouch_pressed and player.horizontal_speed() >= config.slide_entry_speed:
		player.move_and_slide()
		return SLIDE

	# A small downward bias keeps the body glued to the floor across seams and
	# gentle slopes; without it is_on_floor() flickers while running.
	player.velocity.y = -config.floor_snap_speed
	player.move_and_slide()

	if not player.is_on_floor():
		# Leaving the floor here means walking off a ledge, not jumping - the
		# jump path above already returned before this line. Clear the snap
		# bias so a ledge exit starts from a clean zero instead of carrying
		# the downward glue velocity into AirState as a jolt.
		player.velocity.y = 0.0
		return AIR
	return KEEP
