class_name GroundState
extends PlayerState

func enter(_previous: StringName) -> void:
	player.velocity.y = 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	# No sprint key: ground speed is a single top speed, unless the walk
	# modifier (Ctrl) is held, which slows it down deliberately.
	var target_speed: float = config.pawn.walk_velocity if input.walk_held else config.pawn.ground_speed
	player.ground_accelerate(wish_dir, target_speed, delta)

	if player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		return AIR

	# Slide and Vault entry are both gated on player.grounded being TRUE —
	# i.e. already verified by a move_and_slide() this tick or a prior one —
	# not merely assumed. The only time it can be false on entry to
	# GroundState is the tick right after a ScriptedMove (e.g. Vault) hands
	# off: that state deliberately leaves grounded false because its own
	# landing position was driven directly and never checked against real
	# geometry (see VaultState.physics_update()'s note on this). Without this
	# gate, that unverified position was itself enough to immediately chain
	# into a SECOND scripted move — return VAULT below, again without ever
	# calling move_and_slide() — if a further obstacle happened to be in
	# reach. The gate costs nothing on the legitimate path: every real
	# Air/Slide->Ground transition already has grounded==true by the time
	# GroundState runs.
	if player.grounded:
		# A slide has to be earned: crouching below the entry speed just
		# crouches. Gated on a fresh PRESS (never on crouch_held) so holding
		# crouch while running cannot immediately re-enter Slide the instant a
		# slide ends — that would strobe Slide<->Ground every couple of frames
		# instead of committing. The press is read through the buffer rather
		# than straight off this tick's input, so a crouch pressed just before
		# touchdown — which is exactly what a roll is — still opens a slide on
		# landing instead of being discarded in mid-air. The speed test is
		# evaluated FIRST so its short-circuit leaves a too-slow press
		# buffered rather than spending it.
		if player.horizontal_speed() >= config.slide.slide_entry_speed and player.consume_crouch():
			# Same floor-snap bias as the fall-through path below. Without it, a
			# slide started on a downslope can leave the floor on this very tick
			# and bounce straight back out to Air.
			player.velocity.y = -config.pawn.floor_snap_speed
			player.move_and_slide()
			player.set_grounded(player.is_on_floor())
			return SLIDE

		# Vaulting has to be earned with speed, or every waist-high box becomes a
		# free elevator.
		if player.probes != null and player.horizontal_speed() >= config.speed_vault.vault_min_speed:
			if player.probes.vault_query()["valid"]:
				return VAULT

	# Ankle-high clutter would otherwise stop a run dead: Godot has no built-in
	# step-up. Free by design -- no speed cost, no state change -- so the only
	# trace it leaves is the camera easing the rise out.
	var rise: float = player.try_step_up(delta)
	if rise > 0.0 and player.camera_rig != null:
		player.camera_rig.add_step_offset(rise)

	# A small downward bias keeps the body glued to the floor across seams and
	# gentle slopes; without it is_on_floor() flickers while running.
	player.velocity.y = -config.pawn.floor_snap_speed
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
