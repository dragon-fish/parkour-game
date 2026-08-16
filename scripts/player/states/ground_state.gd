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
		player.set_grounded(player.is_on_floor())
		return AIR

	# A slide has to be earned: crouching below the entry speed just crouches.
	# Gated on a fresh PRESS (never on crouch_held) so holding crouch while
	# running cannot immediately re-enter Slide the instant a slide ends —
	# that would strobe Slide<->Ground every couple of frames instead of
	# committing. The press is read through the buffer rather than straight off
	# this tick's input, so a crouch pressed just before touchdown — which is
	# exactly what a roll is — still opens a slide on landing instead of being
	# discarded in mid-air. The speed test is evaluated FIRST so its
	# short-circuit leaves a too-slow press buffered rather than spending it.
	if player.horizontal_speed() >= config.slide_entry_speed and player.consume_crouch():
		# Same floor-snap bias as the fall-through path below. Without it, a
		# slide started on a downslope can leave the floor on this very tick
		# and bounce straight back out to Air.
		player.velocity.y = -config.floor_snap_speed
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		return SLIDE

	# A small downward bias keeps the body glued to the floor across seams and
	# gentle slopes; without it is_on_floor() flickers while running.
	player.velocity.y = -config.floor_snap_speed
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

	if not player.grounded:
		# Leaving the floor here means walking off a ledge, not jumping - the
		# jump path above already returned before this line. Clear the snap
		# bias so a ledge exit starts from a clean zero instead of carrying
		# the downward glue velocity into AirState as a jolt.
		player.velocity.y = 0.0
		return AIR
	return KEEP
