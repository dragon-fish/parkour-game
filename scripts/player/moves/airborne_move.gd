class_name AirborneMove
extends Move

# Shared machinery for every airborne state. The original splits one airborne
# stretch into several TdMove classes that differ ONLY in which probes they
# run (11 §11.2); the physics is identical. Keeping the physics here and
# letting subclasses declare their probe set is what makes those differences
# enforceable instead of advisory.

## Gravity and air control, shared by every airborne state. Terminal velocity
## is clamped here rather than per-state so a subclass cannot forget it and
## produce a body that accelerates forever.
##
## Takes wish_dir as given -- it no longer decides whether input applies.
## FallUncontrolledMove is the one state that has no input at all (03 §3.1 --
## the original hands the controller to PlayerDying at the threshold rather
## than scoring damage on impact, which is why a roll cannot save it), and it
## expresses that by always calling this with Vector3.ZERO rather than by this
## shared function reading a flag on Player.
func apply_air_physics(delta: float, wish_dir: Vector3) -> void:
	player.air_accelerate(wish_dir, delta)
	player.velocity.y -= config.pawn.gravity * delta
	player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)

## Probes this state is allowed to run, in the original's own precedence
## order: wall, then vault, then grab. Returns a target state name, or KEEP
## when nothing fired.
func probe_transition() -> StringName:
	var c := current_config()

	# PRIORITY DECISION: wall running is checked BEFORE the ledge grab below,
	# and wins whenever both are in reach at once. This is deliberate, not an
	# accident of ordering -- ledge_query() is unconditional and was already
	# first here, so leaving the wall check after it would mean the wall check
	# could never win a single contested tick: a player flying fast along a
	# wall who clips any incidental ledge in range would always mantle
	# instead of wall-running, no matter how clearly wall running is what the
	# geometry and their speed are asking for.
	#
	# Grabbing a ledge is a RECOVERY from a misjudged jump -- something that
	# happens to you. Wall running is a ROUTE the player deliberately chose by
	# building speed and running alongside a wall; wall_running_min_speed
	# already gates it on exactly that commitment (see WallRunConfig's own
	# note: wall running CARRIES speed, it does not create it). At speed
	# beside a wall, the wall is what the player is asking for. Was decided by
	# test_a_wall_run_wins_over_a_ledge_grab_when_both_are_in_reach in
	# tests/legacy/test_wall_run.gd for the contested-geometry case -- that
	# test is ARCHIVED and NOT in the running suite, so nothing enforces this
	# today; restore the pin when the behavioural suite is rewritten.
	# ✅ MEASURED (04 §4.1): a wall run can only start from the ORIGINAL's Jump
	# state, never from its Falling state -- all 15 measured airborne entries
	# came from Jump. The two are separated by EnterToFallingZSpeed = -200, i.e.
	# purely by how fast you are already dropping.
	#
	# This project used to fold both of the original's states into one
	# FallingMove and re-express that split as a speed test on velocity.y.
	# Now that Jump and Falling are separate states (both AirborneMove
	# subclasses), the split is expressed directly instead: JumpConfig sets
	# check_for_wall_climb, FallingConfig does not (see FallingConfig's own
	# note on that absence). Without it, any descent that so much as brushes
	# a building would convert into a wall run -- a 40 m drop becoming
	# Spider-Man rather than a death.
	#
	# Measured entry window: -104 .. +510 uu/s of vertical speed, comfortably
	# inside this threshold (-2.0 m/s) at the bottom end. The TOP end is
	# deliberately unbounded: rising fast is fine to attach from, and
	# WallRunningVelocityStartLimit = 300 turned out NOT to be a ceiling on it.
	if c.check_for_wall_climb and player.probes != null \
			and player.horizontal_speed() >= config.wall_run.wall_running_min_speed:
		var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
		var wall: Dictionary = player.probes.wall_query(heading)
		# can_enter() replaces the old note_wall_detach()/can_attach_wall()
		# same-wall cooldown -- see Player's own deletions for that mechanism
		# and this task's report for the accepted risk that removing it opens
		# up (an unbounded zig-zag climb between two facing walls). This gate
		# is now generic to the MOVE, not to which wall: any WALL_RUN re-entry
		# is refused for redo_move_time (0.15 s) after the last one ended,
		# regardless of which wall it was.
		if wall["valid"] and player.move_manager.can_enter(WALL_RUN):
			var incidence: float = wall["incidence"]
			# 0-57 degrees takes the forward branch, 60+ takes the strafe
			# branch (04 §4.1); the 3-degree gap between them is a deliberate
			# hysteresis band. There is no "current branch" to hold onto
			# here -- this check only ever runs BEFORE the move exists, on a
			# player who is not yet wall running -- so landing in the gap
			# simply means neither branch qualifies THIS tick; the player
			# stays in this state and the next tick's fresh query tries again.
			var qualifies: bool = incidence <= config.wall_run.wall_running_forward_max_start_angle \
				or incidence >= config.wall_run.wall_running_strafe_start_angle
			if qualifies:
				return WALL_RUN

	# Checked BEFORE the ledge grab below, mirroring 05 §5.7's own fallback
	# order: a jump that overshoots or undershoots tries the vault table
	# FIRST, and only falls through to "hang and pull up" (GrabMove, the
	# slowest path in the whole move set) once nothing in VaultTypes matches.
	# This is also where autostepuprightleg actually lives in practice: its
	# MinSpeedZ/MaxSpeedZ band (-6.0..0.0) requires already falling, which
	# WalkingMove's own grounded vault check can never see -- see
	# SpeedVaultConfig.variants' own per-field note on that row.
	if c.check_for_vault_over and player.probes != null:
		var hit: Dictionary = player.probes.vault_query()
		if hit["valid"]:
			var variant: Dictionary = config.speed_vault.pick_variant(
				hit["height"], hit["vault_over"], player.velocity.y, player.horizontal_speed())
			if config.speed_vault.should_commit(hit["distance"], player.horizontal_speed(), variant):
				player.pending_vault_variant = variant
				return SPEED_VAULT

	# Checked before this tick's own move_and_slide(), same as the vault check
	# just above: if it fires, this move hands off to GrabMove (which
	# drives the body directly, see its own note) without this tick's physics
	# ever having moved the body at all. can_enter() enforces GrabConfig's own
	# redo_move_time (0.45 s) -- it replaces Player.can_grab_ledge(), the last
	# of the three hand-rolled cooldowns Player used to carry -- so dropping
	# off a ledge cannot instantly re-grab the very same one.
	if c.check_for_grab and player.probes != null and player.move_manager.can_enter(GRAB):
		if player.probes.ledge_query()["valid"]:
			return GRAB

	return KEEP

## Runs this tick's move_and_slide() and, if the body touched down, settles the
## Carries the body through THIS tick and hands off, for the transitions that
## leave one airborne state for another. Without it the hand-off tick covers
## zero distance -- the move returns before settle_landing()'s own
## move_and_slide() -- and Player._travel_speed, which is measured from actual
## displacement, reads zero for one frame. The speed-driven FOV dips and
## springs back, which is visible as a flicker at the exact moment Jump becomes
## Falling.
##
## Landing is deliberately NOT settled here: a tick that both crosses a
## threshold and touches down is judged by the state it is handing off TO, one
## tick later. That is the existing rule (see JumpMove's own note on the
## descent being what the landing is judged on), and it survives because the
## fall tracker has already counted this tick's descent.
func advance_and_hand_off(destination: StringName) -> StringName:
	player.move_and_slide()
	player.set_grounded(player.is_on_floor())
	return destination

## landing. Returns the state to hand off to, or KEEP while still airborne.
func settle_landing(delta: float) -> StringName:
	# Capture the impact speed before move_and_slide() zeroes it on contact.
	var impact_speed := maxf(-player.velocity.y, 0.0)
	player.move_and_slide()

	if not player.is_on_floor():
		player.set_grounded(false)
		return KEEP

	# Player._physics_process() already fed fall_tracker THIS tick, but
	# before this move ran -- so that call only ever sees LAST tick's
	# velocity/position. This tick's own descent, the one that actually
	# ends in the floor contact just detected, was never counted, and is
	# about to be thrown away by set_grounded() below. One more update(),
	# using the pre-impact velocity already captured as impact_speed and
	# the just-landed position, folds that final increment in before the
	# reset -- otherwise every fall undercounts by ~one tick's worth of
	# descent (~0.09 m at 5.6 m/s, 1/60 s), which is exactly the kind of
	# error a task calibrating fall-height THRESHOLDS cannot absorb.
	player.fall_tracker.update(delta, -impact_speed, player.global_position.y)
	# Read BEFORE set_grounded(), which resets the counter.
	var fall_height: float = player.fall_tracker.fall_height
	# fall_height must gate consume_roll(), not the other way round: `and`
	# short-circuits left-to-right, so with consume_roll() on the left it
	# would ALWAYS spend the buffered press -- even on a landing nowhere
	# near the roll threshold -- eating a crouch meant for the slide-entry
	# check in walking_move.gd on the very next tick. Keeping the height
	# check first means an ordinary landing leaves the buffer untouched.
	var rolled: bool = fall_height >= config.pawn.skill_roll_landing_height \
		and player.consume_roll()
	player.last_landing_rolled = rolled
	player.last_landing_fall_height = fall_height
	player.set_grounded(true)
	player.notify_landed(impact_speed)
	_apply_landing_cost(fall_height, rolled)
	return landing_destination(fall_height, rolled)

## Where a landing from this state leads. Overridden by subclasses.
## FallUncontrolledMove overrides this to emit died_from_fall instead of
## returning WALKING directly -- the death is now a property of WHICH STATE
## landed, not of a flag read here.
##
## The default case now also judges the hard-unrolled lockout: only a landing
## AT OR ABOVE hard_landing_height that was NOT rolled out of pays the 2 s
## Landing penalty. Below the threshold a landing costs nothing at all (03
## §3.1), so pausing the player there would be a penalty the original does
## not levy; rolling is the player's own escape from a landing that otherwise
## would have paid it.
func landing_destination(fall_height: float, rolled: bool) -> StringName:
	if fall_height >= config.pawn.hard_landing_height and not rolled:
		return LANDING
	return WALKING

## Landing bleeds horizontal speed according to which of the four confirmed
## tiers the ACCUMULATED FALL HEIGHT falls into -- never according to this
## frame's vertical speed. See Player.landing_keep_ratio().
func _apply_landing_cost(fall_height: float, rolled: bool) -> void:
	var keep: float = player.landing_keep_ratio(fall_height, rolled)
	player.velocity.x *= keep
	player.velocity.z *= keep
