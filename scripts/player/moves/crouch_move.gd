class_name CrouchMove
extends Move

# The standing-crouch half of GBA_Crouch's downward branch: slow, low-profile
# movement, reached today only from a Slide that decayed or timed out while
# the key was still held (see SlideMove's own comment on that hand-off).
# Capsule is the same compressed height a slide already uses, so the hand-off
# never pops the collider and never reopens a headroom problem the slide had
# already solved for this exact spot.

func enter(_previous: StringName) -> void:
	player.set_capsule_height(config.crouch.crouch_capsule_height)

## See SlideMove.exit()'s own comment on why this is a REQUEST, not an
## unconditional restore: an exit that walks off a ledge (-> Falling) must still
## be allowed to fall crouched-and-clipping-nothing rather than being forced
## to stand into a roof that is still there. Player.request_standing_capsule()
## restores at once when there is room, or defers until there is.
func exit() -> void:
	player.request_standing_capsule()

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	var target_speed: float = player.speed_cap() * cfg.speed_modifier
	var grade: float = player.ground_grade(Vector3(player.velocity.x, 0.0, player.velocity.z))
	player.ground_accelerate(wish_dir, target_speed, delta, grade)

	# Same ankle-high clutter allowance Walking and Slide get: a crouched walk
	# stopped dead by a kerb reads as sticky geometry, not as a rule.
	var rise: float = player.try_step_up(delta)
	if rise > 0.0 and player.camera_rig != null:
		player.camera_rig.add_step_offset(rise)

	# Same floor-snap bias as Walking/Slide, so a crouched walk does not
	# flicker off gentle slopes or floor seams.
	player.velocity.y = -config.pawn.floor_snap_speed
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())

	if not player.grounded:
		player.velocity.y = 0.0
		return FALLING

	# Releasing the key asks to stand -- but only granted when there is
	# headroom for the standing capsule, reusing the exact machinery Slide
	# already relies on (Player.has_headroom()/request_standing_capsule()).
	# Held under a low roof, the player stays crouched and can keep moving.
	if not input.crouch_held and player.has_headroom():
		return WALKING

	return KEEP
