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

	# Checked before this tick's own move_and_slide(), same as GroundState's
	# vault check: if it fires, this state hands off to LedgeHangState (which
	# drives the body directly, see its own note) without this tick's physics
	# ever having moved the body at all. can_grab_ledge() enforces the
	# post-release cooldown so dropping off a ledge cannot instantly re-grab
	# the very same one.
	if player.probes != null and player.can_grab_ledge():
		if player.probes.ledge_query()["valid"]:
			return LEDGE

	# Capture the impact speed before move_and_slide() zeroes it on contact.
	var impact_speed := maxf(-player.velocity.y, 0.0)
	player.move_and_slide()

	if player.is_on_floor():
		player.set_grounded(true)
		player.notify_landed(impact_speed)
		_apply_landing_cost(impact_speed, input)
		return GROUND
	player.set_grounded(false)
	return KEEP

## Landing bleeds horizontal speed in proportion to how hard the impact was.
## Rolling — crouch held on a fast enough landing — bleeds far less. Neither
## path ever ADDS speed, so a landing can only ever cost momentum.
func _apply_landing_cost(impact_speed: float, input: MoveInput) -> void:
	# land_cost_speed_ref, NOT the camera's land_dip_speed_ref: the two happen
	# to share a default, but they are independent knobs. Reading the camera
	# value here meant tuning how hard the view drops silently retuned how much
	# momentum a landing costs.
	var severity := clampf(impact_speed / maxf(config.land_cost_speed_ref, 0.001), 0.0, 1.0)
	var rolled: bool = input.crouch_held and impact_speed >= config.roll_min_fall_speed
	player.last_landing_rolled = rolled

	# Clamped to 1.0 so the invariant above holds for every reachable config.
	# The tuning panel generates each slider's range as default * 3, which puts
	# both keep ratios well past 1.0 — without this clamp, a slider drag could
	# make landing a source of free speed.
	var keep_at_full: float = minf(config.roll_speed_keep if rolled else config.land_speed_keep, 1.0)
	var keep := lerpf(1.0, keep_at_full, severity)
	player.velocity.x *= keep
	player.velocity.z *= keep
