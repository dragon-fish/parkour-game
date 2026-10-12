class_name AirborneMove
extends Move

# Shared machinery for every airborne state. [ME:CONFIRMED 11 §11.2] The
# original splits one airborne stretch into several TdMove classes that
# differ ONLY in which probes they run; the physics is identical. Keeping the
# physics here and letting subclasses declare their probe set is what makes
# those differences enforceable instead of advisory.

## Gravity and air control, shared by every airborne state. Terminal velocity
## is clamped here rather than per-state so a subclass cannot forget it and
## produce a body that accelerates forever.
##
## Takes wish_dir as given -- it no longer decides whether input applies.
## FallUncontrolledMove is the one state that has no input at all
## ([ME:CONFIRMED 03 §3.1] the original hands the controller to PlayerDying at
## the threshold rather than scoring damage on impact, which is why a roll
## cannot save it), and it expresses that by always calling this with
## Vector3.ZERO rather than by this shared function reading a flag on Player.
func apply_air_physics(delta: float, wish_dir: Vector3) -> void:
	player.air_accelerate(wish_dir, delta)
	# effective_gravity(): free flight honours the player's gravity window.
	player.velocity.y -= player.effective_gravity() * delta
	player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)

## The environment probes this state is allowed to run. See
## Move.legacy_probe_transition().
func probe_transition() -> StringName:
	return legacy_probe_transition()


## Settles the landing. Returns the state to hand off to, or KEEP while
## still airborne.
func settle_landing(delta: float) -> StringName:
	# Capture the impact speed before move_and_slide() zeroes it on contact.
	var impact_speed := maxf(-player.velocity.y, 0.0)
	# Asked BEFORE the move, like the soft landing's arc: landing on a chute as
	# a floor loses the fall's speed down it, and the slide begins leaving
	# the surface it just touched.
	var chute_ahead: bool = takes_chute() and player.chute_ahead(player.velocity * delta)
	if chute_ahead:
		player.use_chute_floor(true)
	player.move_and_slide()
	if chute_ahead:
		player.use_chute_floor(false)

	# A marked chute is a surface but not a floor: touching it, from any
	# angle, is the start of the slide, not a landing. Checked before the
	# floor test because a chute steeper than floor_max_angle never reads as
	# a floor at all. [ME:COMMUNITY] A fall past hard_landing_height onto the
	# chute costs the hard landing's health and its red, and slides on with
	# no stagger; an UNCONTROLLED fall is not saved by the chute (takes_chute()
	# below), it lands on it as on anything and dies.
	var on_chute: bool = not player.touched_chute().is_empty()
	if on_chute and takes_chute():
		player.fall_tracker.update(delta, -impact_speed, player.global_position.y)
		var chute_fall: float = player.fall_tracker.fall_height
		if chute_fall >= config.pawn.hard_landing_height:
			player.take_damage(config.landing.hard_landing_damage, Health.Cause.HARD_LANDING)
			# The red is the slide's to show and fade: a tint set here would
			# outlive the landing, with no move left to take it down.
			player.pending_chute_hurt = true
		player.set_grounded(true)
		# The slide reads the chute it starts on from the physics' finding.
		player.uncontrolled_slide_normal = player.touched_chute().get("normal", Vector3.UP)
		return RAMP_SLIDE

	if not player.is_on_floor() and not on_chute:
		player.set_grounded(false)
		return KEEP

	player.fall_tracker.update(delta, -impact_speed, player.global_position.y)
	player.last_landing_fall_height = player.enter_falling_height - player.collision_center().y
	player.last_landing_coiled = player.coiled_since_ground
	player.set_grounded(true)
	player.notify_landed(impact_speed)
	if not uses_original_landing():
		return _legacy_landing(delta)
	# APawn::processLanded: the original's landing, the same one PawnPhysics
	# runs for the ported airborne moves -- falling damage, this move's
	# landed() (Landing, by default), and the post-landing walking physics.
	player.pawn_landed(player.get_floor_normal())
	if player.physics == PHYS_FALLING:
		player.set_physics(PHYS_WALKING)
	# Declared again for whichever move the landing handed the body to.
	player.set_grounded(true)
	return KEEP

## Whether this move's touchdown goes through the original's landing
## (Player.pawn_landed() and LandingMove). Only FallUncontrolledMove keeps a
## landing of its own: the original replaces Landed in its UncontrolledFall
## state as well.
func uses_original_landing() -> bool:
	return true

## This project's own landing, for the moves uses_original_landing() keeps out
## of the original's.
func _legacy_landing(_delta: float) -> StringName:
	var fall_height: float = player.last_landing_fall_height
	var on_back: bool = player.consume_back_landing()
	var rolled: bool = not on_back \
		and not player.statuses.is_move_blocked(SKILL_ROLL) \
		and fall_height >= config.pawn.skill_roll_landing_height \
		and player.consume_roll()
	player.last_landing_rolled = rolled
	player.enter_falling_height = player.collision_center().y
	if player.physics == PHYS_FALLING:
		player.set_physics(PHYS_WALKING)
	var hurt: float = landing_damage(fall_height, rolled)
	if hurt > 0.0:
		player.take_damage(hurt, Health.Cause.HARD_LANDING)
	if on_back:
		if hurt > 0.0:
			player.pending_stagger_tint = config.landing.tint_color
		return LAY_ON_GROUND
	return landing_destination(fall_height, rolled)


## Where a fall past falling_uncontrolled_height loses control to, or KEEP
## short of it. For the states holding both bCheckExitToUncontrolledFalling and
## bCheckForSoftLanding [ME:CONFIRMED 11 §11.2] -- Falling and 180TurnInAir.
##
## [ME:CONFIRMED 12 §12.5] ONE CHECK, AT THE MOMENT CONTROL IS LOST, and never
## again. The original asks whether the arc ends on something soft exactly
## here; what it buys is which state the body loses control INTO, not whether
## it loses control at all. A pad does not hand the fall back -- the player is
## a passenger either way, and the difference shows up on impact.
##
## Asked before the death rather than from inside it, unlike the original,
## because FallUncontrolledMove.enter() starts a ragdoll and stops the capsule
## on its first tick and pulling a body back out of that is far harder than
## never putting it in.
func lose_control() -> StringName:
	if player.fall_tracker.fall_height < config.pawn.falling_uncontrolled_height:
		return KEEP
	var arc: Dictionary = player.probes.predicted_landing(player.velocity)
	if not arc.is_empty() and Probes.is_soft(arc.get("collider")):
		return SOFT_LANDING
	return FALL_UNCONTROLLED

## Whether touching a marked chute starts the slide. Every controlled fall
## says yes; the uncontrolled one overrides this to land on the chute as on
## any surface, which is fatal.
func takes_chute() -> bool:
	return true

## What arriving costs the body, in health.
##
## [ME:CONFIRMED 03 §3.1, 13.1] HardLandingDamage = 15 and does NOT scale with
## height -- 7 m and 9 m both cost exactly that. The player never has to
## estimate how bad a landing was: missing the roll costs what it costs.
##
## A ROLL PAYS NOTHING, which is the whole trade the move exists for.
func landing_damage(fall_height: float, rolled: bool) -> float:
	if rolled or fall_height < config.pawn.hard_landing_height:
		return 0.0
	return config.landing.hard_landing_damage


## Where a landing from this state leads. Overridden by subclasses.
## FallUncontrolledMove overrides this to emit died_from_fall instead of
## returning WALKING directly -- the death is a property of WHICH STATE
## landed, not of a flag read here.
##
## The default case also judges the hard-unrolled lockout: only a landing AT
## OR ABOVE hard_landing_height that was NOT rolled out of pays the 2 s
## Landing penalty. [ME:CONFIRMED 03 §3.1] Below the threshold a landing
## costs nothing at all, so pausing the player there would be a penalty the
## original does not levy; rolling is the player's own escape from a landing
## that otherwise would have paid it.
func landing_destination(fall_height: float, rolled: bool) -> StringName:
	# A roll is a MOVE now, not merely a discount applied on the way to
	# Walking. The original gives it its own TdMove with its own controller
	# state and look clamp, and the manoeuvre visibly owns the body for a
	# moment -- which a boolean read once at touchdown cannot express.
	if rolled:
		return SKILL_ROLL
	if fall_height >= config.pawn.hard_landing_height:
		return LANDING
	# Still in the coil's capsule: CROUCH decides when to stand, for the reason
	# CoilMove.landing_destination() gives -- a coil lands where a standing
	# body may not fit, a duct above all.
	if player.coil_capsule_held:
		return CROUCH
	return WALKING
