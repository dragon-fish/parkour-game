class_name WalkingMove
extends Move

func enter(_previous: StringName) -> void:
	player.velocity.y = 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	# No sprint key: the curve IS the sprint (02 §2.1). The walk modifier is
	# the one thing that overrides it, with its own confirmed hard cap.
	var target_speed: float = config.pawn.walk_velocity if input.walk_held \
		else player.speed_cap() * cfg.speed_modifier
	var grade: float = player.ground_grade(Vector3(player.velocity.x, 0.0, player.velocity.z))
	player.ground_accelerate(wish_dir, target_speed, delta, grade)

	if player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z
		player.velocity += player.jump_add_velocity(input)
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		return JUMP

	# Slide and Vault entry are both gated on player.grounded being TRUE —
	# i.e. already verified by a move_and_slide() this tick or a prior one —
	# not merely assumed. The only time it can be false on entry to
	# WalkingMove is the tick right after a ScriptedMove (e.g. SpeedVault) hands
	# off: that move deliberately leaves grounded false because its own
	# landing position was driven directly and never checked against real
	# geometry (see SpeedVaultMove.physics_update()'s note on this). Without this
	# gate, that unverified position was itself enough to immediately chain
	# into a SECOND scripted move — return SPEED_VAULT below, again without ever
	# calling move_and_slide() — if a further obstacle happened to be in
	# reach. The gate costs nothing on the legitimate path: every real
	# Falling/Slide->Walking transition already has grounded==true by the time
	# WalkingMove runs.
	if player.grounded:
		# A slide has to be earned: crouching below the entry speed just
		# crouches. Gated on a fresh PRESS (never on crouch_held) so holding
		# crouch while running cannot immediately re-enter Slide the instant a
		# slide ends — that would strobe Slide<->Walking every couple of frames
		# instead of committing. The press is read through the buffer rather
		# than straight off this tick's input, so a crouch pressed just before
		# touchdown — which is exactly what a roll is — still opens a slide on
		# landing instead of being discarded in mid-air.
		# GBA_Crouch is one key with five outlets (05 §5.2, confirmed by in-game
		# measurement), and only three discriminators: airborne or touching down,
		# horizontal speed, accumulated fall height.
		#   airborne, speed >= 1.0        -> Coil          (OUT OF SCOPE, no such move)
		#   airborne, speed <  1.0        -> nothing
		#   touchdown, fall >= 2.0 m      -> Roll          (AirborneMove.settle_landing(), shared by Jump/Falling)
		#   touchdown, fall <  2.0 m, moving -> Slide      (here)
		#   grounded, not moving          -> Crouch
		# There are no chords, no hold-versus-tap, no direction modifiers.
		if player.consume_roll():
			if player.horizontal_speed() >= config.slide.slide_abort_speed:
				# Same floor-snap bias as the fall-through path below. Without
				# it, a slide started on a downslope can leave the floor on
				# this very tick and bounce straight back out to Falling.
				player.velocity.y = -config.pawn.floor_snap_speed
				player.move_and_slide()
				player.set_grounded(player.is_on_floor())
				return SLIDE
			# The table's last row, which used to have no code behind it: too
			# slow to earn a slide is not "nothing happens", it is a crouch.
			# The press is spent either way now -- leaving it buffered was only
			# ever correct while this branch had nowhere to send it, and it
			# meant a crouch held while standing still did nothing at all.
			return CROUCH

		# Vaulting has to be earned with speed, or every waist-high box becomes a
		# free elevator -- see SpeedVaultConfig.pick_variant()'s own entry
		# gates, which is where that requirement actually lives now (05 §5.7:
		# six variants, gated differently by height/momentum/vertical speed,
		# not one flat speed switch). Commitment fires up to
		# max_distance_time SECONDS before contact, not at a fixed distance --
		# see SpeedVaultConfig.should_commit()'s own comment for why that is a
		# deliberate reading of the source data, not a typo.
		if player.probes != null and current_config().check_for_vault_over:
			var hit: Dictionary = player.probes.vault_query()
			if hit["valid"]:
				var variant: Dictionary = config.speed_vault.pick_variant(
					hit["height"], hit["vault_over"], player.velocity.y, player.horizontal_speed())
				if config.speed_vault.should_commit(hit["distance"], player.horizontal_speed(), variant):
					player.pending_vault_variant = variant
					return SPEED_VAULT

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
		# ...unless a step-up just fired. It lifts the body in place and lets
		# move_and_slide() carry it forward onto the step, so that tick always
		# ends airborne by construction. Falling for one tick here is what
		# handed a 0.30 m kerb to FallingMove's ledge probe, which grabbed it.
		if player.in_step_grace():
			return KEEP
		# Leaving the floor here means walking off a ledge, not jumping - the
		# jump path above already returned before this line. Clear the snap
		# bias so a ledge exit starts from a clean zero instead of carrying
		# the downward glue velocity into FallingMove as a jolt.
		player.velocity.y = 0.0
		return FALLING
	return KEEP
