class_name WalkingMove
extends Move

func enter(_previous: StringName) -> void:
	player.velocity.y = 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	# THE LADDER, first: an authored interest point beats ordinary ground
	# movement the instant the body's front is inside its frontal volume. A
	# ladder is caught by walking straight into it from the ground, exactly
	# the way a jump onto a cable catches from the air. No check_for_ladder
	# flag here (that switch is airborne-only, see MoveConfig's own note) --
	# the ground entry is unconditional, gated only by the same frontal fan
	# every other entry site asks. The ledge and beam blocks below ask the
	# identical question through their own catch_gate()s.
	if player.grounded and player.move_manager.can_enter(LADDER):
		var rail: InterestLine = player.nearest_interest_line(InterestLine.Kind.LADDER)
		if rail != null and LadderMove.catch_gate(player, rail):
			return LADDER

	# Same reasoning as the ladder above -- see its own comment.
	if player.grounded and player.move_manager.can_enter(LEDGE_WALK):
		var ledge: InterestLine = player.nearest_interest_line(InterestLine.Kind.LEDGE_WALK)
		if ledge != null and LedgeWalkMove.catch_gate(
				player, ledge, config.ledge_walk.foot_snap_height):
			return LEDGE_WALK

	# Same reasoning as the ladder above -- see its own comment.
	if player.grounded and player.move_manager.can_enter(BALANCE):
		var beam: InterestLine = player.nearest_interest_line(InterestLine.Kind.BALANCE)
		if beam != null and BalanceMove.catch_gate(
				player, beam, config.balance.foot_snap_height):
			return BALANCE

	var wish_dir: Vector3 = player.wish_direction(input)
	# [ME:CONFIRMED 02 §2.1] No sprint key: the curve IS the sprint. The walk
	# modifier is the one thing that overrides it, with its own confirmed hard
	# cap.
	var target_speed: float = config.pawn.walk_velocity if input.walk_held \
		else player.speed_cap() * cfg.speed_modifier
	var grade: float = player.ground_grade(Vector3(player.velocity.x, 0.0, player.velocity.z))
	player.ground_accelerate(wish_dir, target_speed, delta, grade)

	# A SPRING BOARD OUTRANKS A PLAIN JUMP. [ME:CONFIRMED] the owner, in the
	# original: two foot plants ahead and the jump key IS the spring board.
	# Asked on the press only, and only from the ground -- the original never
	# enters this from the air. Standing room on both plants is Player's
	# question, not the probe's, the same split ledge_query() keeps.
	if player.grounded and input.jump_pressed and player.probes != null \
			and player.move_manager.can_enter(SPRING_BOARD):
		var board: Dictionary = player.probes.springboard_query()
		if board["valid"] and player.fits_standing_at(board["plant_1"]) \
				and player.fits_standing_at(board["plant_2"]):
			# Spent here so the buffered press cannot fire a second jump on
			# the way down; refused only by a level's own jump block, in
			# which case the plain jump below is refused the same way.
			if player.consume_jump():
				player.pending_spring_board = board
				return SPRING_BOARD

	if player.consume_jump():
		# A DODGE IS WHAT A JUMP IS WHEN THE STRAFE AXIS IS PUSHED, and that
		# INCLUDES a diagonal: [ME:CONFIRMED 04 §4.5] W+A and space fires a
		# left dodge in the original. So this is not a rare special case
		# reachable only from a pure sidestep -- it takes over every jump made
		# while a strafe key is down, and running diagonally is the common
		# way to be in that position. DodgeJumpConfig.strafe_threshold is
		# where that reading is argued.
		#
		# Sharing consume_jump() with the plain jump below rather than asking
		# for the press separately: coyote time, the jump buffer and a level's
		# own jump block are all decided in there, and a dodge is a jump for
		# every one of those purposes.
		var dodge: Vector3 = player.dodge_direction(input)
		var next: StringName = JUMP
		if dodge == Vector3.ZERO:
			player.velocity.y = config.pawn.base_jump_z
			player.velocity += player.jump_add_velocity(input)
		else:
			# SPENT ONCE, HERE, AS A WORLD VECTOR -- see DodgeJumpMove's own
			# note on why it must never be recomputed against the facing.
			var dodge_cfg: DodgeJumpConfig = config.dodge_jump
			player.velocity.y = dodge_cfg.base_jump_z
			player.velocity += dodge * dodge_cfg.jump_add_xy
			# THE WHOLE COST OF THE MOVE. The speed already in the body is
			# left alone; what is taken is the ceiling holding it up. See
			# DodgeJumpConfig on why InertiaConservation is not applied on
			# top of this.
			player.speed_energy.spend_to_base()
			player.pending_dodge_side = 1 if input.strafe_axis > 0.0 else -1
			next = DODGE_JUMP
		player.move_and_slide()
		player.set_grounded(player.is_on_floor())
		return next

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
		# [ME:CONFIRMED 05 §5.2] GBA_Crouch is one key with five outlets, and
		# only three discriminators: airborne or touching down, horizontal
		# speed, accumulated fall height. The coil row sits beside the roll row
		# without either stealing the other's press because only JumpMove offers
		# a coil -- see MoveConfig.check_for_coil.
		#   airborne, speed >= 1.0        -> Coil          (JumpMove, and only there)
		#   airborne, speed <  1.0        -> nothing
		#   touchdown, fall >= 2.0 m      -> Roll          (AirborneMove.settle_landing(), shared by Jump/Falling)
		#   touchdown, fall <  2.0 m, moving -> Slide      (here)
		#   grounded, not moving          -> Crouch
		# There are no chords, no hold-versus-tap, no direction modifiers.
		# GBA_Crouch has five outlets and this branch owns two of them, on a
		# single press. A level that forbids sliding has not forbidden
		# crouching, so a blocked slide falls through to the crouch row rather
		# than eating the press. Crouch itself is unblockable -- Status.Effect
		# has no BLOCK_CROUCH, deliberately -- so one outlet is always open
		# and the press is always spendable here.
		# [ME:CONFIRMED] Owner: the original cannot enter a slide sideways or
		# backwards. Judged on the SAME arc the ground speed limit uses, so
		# there is one answer to "is this forwards" rather than two that drift
		# apart -- and on travel rather than input, so coasting still slides.
		var slide_blocked: bool = player.statuses.is_move_blocked(SLIDE)
		var wants_slide: bool = not slide_blocked \
			and player.in_forward_arc(player.wish_direction(input) \
				if player.wish_direction(input) != Vector3.ZERO \
				else Vector3(player.velocity.x, 0.0, player.velocity.z)) \
			and player.horizontal_speed() >= config.slide.slide_abort_speed
		if player.consume_roll():
			if wants_slide:
				# Same floor-snap bias as the fall-through path below. Without
				# it, a slide started on a downslope can leave the floor on
				# this very tick and bounce straight back out to Falling.
				player.velocity.y = -config.pawn.floor_snap_speed
				player.move_and_slide()
				player.set_grounded(player.is_on_floor())
				return SLIDE
			# The table's last row: too slow to earn a slide is not "nothing
			# happens" -- it is a crouch. The press must be spent here too,
			# never left buffered, or a crouch held while standing still does
			# nothing at all.
			return CROUCH

		# Vaulting has to be earned with speed, or every waist-high box becomes a
		# free elevator -- see SpeedVaultConfig.pick_variant()'s own entry
		# gates, which is where that requirement actually lives. [ME:CONFIRMED
		# 05 §5.7] TdMove_SpeedVault defines six variants, gated by
		# height/momentum/vertical speed, not one flat speed switch.
		# Commitment fires up to max_distance_time SECONDS before contact, not
		# at a fixed distance -- see SpeedVaultConfig.should_commit()'s own
		# comment for why that is a deliberate reading of the source data, not
		# a typo.
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
	# ANY rise, however small. A threshold here was tried and made things worse:
	# a step often arrives over two or three ticks (0.299, then 0.077, 0.037,
	# 0.012 as the body creeps onto it), and the ones below the threshold moved
	# the body without compensating the camera -- which is a hard jump, exactly
	# the flicker the offset exists to prevent. Ramps are refused inside
	# try_step_up() now, so anything that still produces a rise is a real step.
	if rise > 0.0 and player.camera_rig != null:
		player.camera_rig.add_step_offset(rise)

	# A small downward bias keeps the body glued to the floor across seams and
	# gentle slopes; without it is_on_floor() flickers while running.
	player.velocity.y = -config.pawn.floor_snap_speed
	player.move_and_slide()
	# Geometry can throw the body clear of the floor for a tick -- riding up and
	# off a small sloped obstacle does exactly that -- and without this the tick
	# reads as a ledge exit and cancels the move. See Player.try_step_down().
	# `or` the step-down: moving the body directly does not refresh
	# is_on_floor(), so its own answer is what says the body was caught.
	var stepped_down: bool = player.try_step_down()
	player.set_grounded(player.is_on_floor() or stepped_down)

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

## The playback-rate hook (CharacterAnimator._drive_speed): while the body is
## stepping round on the spot, the Turn90 clip plays at
## PawnConfig.turn_in_place_clip_scale; 0 otherwise leaves the speed match
## alone. The step itself lives on Player (_drive_body_yaw), since it is
## about the visible body and not a move of its own; this is only where the
## animator is told how fast the clip goes.
func clip_time_scale() -> float:
	return player.turn_in_place_clip_scale()
