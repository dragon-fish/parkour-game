class_name CrouchMove
extends Move

# [ME:CONFIRMED 05 §5.2] CrouchMove is the standing-crouch half of
# GBA_Crouch's downward branch: slow, low-profile movement.
#
# Reached today only from a Slide that decayed or timed out while the key was
# still held (see SlideMove's own comment on that hand-off). Capsule is the
# same compressed height a slide already uses, so the hand-off never pops the
# collider and never reopens a headroom problem the slide had already solved
# for this exact spot.

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
	var target_speed: float = player.ground_ceiling(input)
	var grade: float = player.ground_grade(Vector3(player.velocity.x, 0.0, player.velocity.z))
	player.ground_accelerate(wish_dir, target_speed, delta, grade)

	# Same ankle-high clutter allowance Walking and Slide get: a crouched walk
	# stopped dead by a kerb reads as sticky geometry, not as a rule.
	var rise: float = player.try_step_up(delta)
	# ANY rise, however small. A threshold here was tried and made things worse:
	# a step often arrives over two or three ticks (0.299, then 0.077, 0.037,
	# 0.012 as the body creeps onto it), and the ones below the threshold moved
	# the body without compensating the camera -- which is a hard jump, exactly
	# the flicker the offset exists to prevent. Ramps are refused inside
	# try_step_up() now, so anything that still produces a rise is a real step.
	if rise > 0.0 and player.camera_rig != null:
		player.camera_rig.add_step_offset(rise)

	# Same floor-snap bias as Walking/Slide, so a crouched walk does not
	# flicker off gentle slopes or floor seams.
	# See Player.move_on_floor().
	player.move_on_floor()
	# Geometry can throw the body clear of the floor for a tick -- riding up and
	# off a small sloped obstacle does exactly that -- and without this the tick
	# reads as a ledge exit and cancels the move. See Player.try_step_down().
	# `or` the step-down: moving the body directly does not refresh
	# is_on_floor(), so its own answer is what says the body was caught.
	var stepped_down: bool = player.try_step_down()
	player.set_grounded(player.is_on_floor() or stepped_down)

	if not player.grounded:
		# A step-up lifts the body in place and lets move_and_slide() carry it
		# forward onto the step, so the tick it fires ALWAYS ends airborne --
		# by construction, not by accident. Reading that tick as "walked off a
		# ledge" is what turned riding a 0.30 m kerb into
		# Slide -> Falling -> Grab -> Falling -> Walking: the slide was
		# cancelled by clutter it had successfully ridden over, and the same
		# airborne tick handed the kerb to the ledge probe.
		if player.in_step_grace():
			return KEEP
		player.velocity.y = 0.0
		return FALLING

	# Releasing the key asks to stand -- but only granted when there is
	# headroom for the standing capsule, reusing the exact machinery Slide
	# already relies on (Player.has_headroom()/request_standing_capsule()).
	# Held under a low roof, the player stays crouched and can keep moving.
	if not input.crouch_held and player.has_headroom():
		return WALKING

	return KEEP
