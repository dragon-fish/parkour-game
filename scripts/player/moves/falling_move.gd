class_name FallingMove
extends Move

## The original splits one airborne stretch into two move classes whose probe
## switches differ: TdMove_Jump can start a wall climb, TdMove_Falling cannot
## (05 §5.7 ③). Reproduced here as one move with two configs rather than two
## registered moves, so landing detection, the wall check and the ledge check
## stay in one place instead of being duplicated across a pair.
func current_config() -> MoveConfig:
	return config.jump if player.velocity.y > 0.0 else config.falling

func physics_update(delta: float, input: MoveInput) -> StringName:
	var wish_dir: Vector3 = player.wish_direction(input)
	player.air_accelerate(wish_dir, delta)

	# Coyote time: Player.consume_jump() already gates on the timer, so a jump
	# buffered just after walking off a ledge still fires here.
	if player.consume_jump():
		player.velocity.y = config.pawn.base_jump_z

	player.velocity.y -= config.pawn.gravity * delta
	player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)

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
	# building speed and running alongside a wall; wall_min_speed already
	# gates it on exactly that commitment (see WallRunConfig's own note: wall
	# running CARRIES speed, it does not create it). At speed beside a wall,
	# the wall is what the player is asking for. Was decided by
	# test_a_wall_run_wins_over_a_ledge_grab_when_both_are_in_reach in
	# tests/legacy/test_wall_run.gd for the contested-geometry case -- that
	# test is ARCHIVED by Task 1 and NOT in the running suite, so nothing
	# enforces this today; restore the pin when the behavioural suite is
	# rewritten.
	if player.probes != null and player.horizontal_speed() >= config.wall_run.wall_min_speed:
		var wall: Dictionary = player.probes.wall_query()
		if wall["valid"] and player.can_attach_wall(wall["normal"]):
			return WALL_RUN

	# Checked before this tick's own move_and_slide(), same as WalkingMove's
	# vault check: if it fires, this move hands off to GrabMove (which
	# drives the body directly, see its own note) without this tick's physics
	# ever having moved the body at all. can_grab_ledge() enforces the
	# post-release cooldown so dropping off a ledge cannot instantly re-grab
	# the very same one.
	if player.probes != null and player.can_grab_ledge():
		if player.probes.ledge_query()["valid"]:
			return GRAB

	# Capture the impact speed before move_and_slide() zeroes it on contact.
	var impact_speed := maxf(-player.velocity.y, 0.0)
	player.move_and_slide()

	if player.is_on_floor():
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
		return WALKING
	player.set_grounded(false)
	return KEEP

## Landing bleeds horizontal speed according to which of the four confirmed
## tiers the ACCUMULATED FALL HEIGHT falls into -- never according to this
## frame's vertical speed. See Player.landing_keep_ratio().
func _apply_landing_cost(fall_height: float, rolled: bool) -> void:
	var keep: float = player.landing_keep_ratio(fall_height, rolled)
	player.velocity.x *= keep
	player.velocity.z *= keep
