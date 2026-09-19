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
	# [ME:CONFIRMED 04 §4.1] A wall run can only start from the ORIGINAL's Jump
	# state, never from its Falling state -- all 15 measured airborne entries
	# came from Jump. The two are separated by EnterToFallingZSpeed = -200, i.e.
	# purely by how fast you are already dropping.
	#
	# Jump and Falling are separate states (both AirborneMove subclasses), and
	# the split is expressed directly: JumpConfig sets check_for_wall_climb,
	# FallingConfig does not (see FallingConfig's own note on that absence).
	# DO NOT let Falling set it too -- any descent that so much as brushes a
	# building would convert into a wall run, a 40 m drop becoming Spider-Man
	# rather than a death.
	#
	# Measured entry window: -104 .. +510 uu/s of vertical speed, comfortably
	# inside this threshold (-2.0 m/s) at the bottom end. The TOP end is
	# deliberately unbounded: rising fast is fine to attach from, and
	# WallRunningVelocityStartLimit = 300 turned out NOT to be a ceiling on it.
	# KICKING STRAIGHT UP IS TESTED BEFORE RUNNING ALONG, and has to be: the
	# head-on band (0-33 degrees) sits INSIDE the wall run's forward band
	# (0-57), so whichever is asked first wins every head-on approach outright.
	#
	# The original has one bCheckForWallClimb flag covering both moves, which
	# means the choice is made downstream of the flag, and the angle is the
	# only thing in the data with numbers attached: 33 / 57 / 60 tile the
	# quarter-circle exactly once. Asking the narrower band first is what makes
	# that tiling real rather than decorative -- see WallClimbConfig's own note.
	#
	# This is also why the wall run's forward branch below is UNCHANGED at 57
	# rather than being narrowed to 33-57. Narrowing it would be the same
	# behaviour expressed twice, and the second copy would rot.
	# NO SPEED GATE, unlike the wall run's -- DO NOT add one. [ME:CONFIRMED]
	# Standing still, pressed against a wall, W and space climbs in the
	# original. What gates a climb instead is INTENT, which is what
	# approach_direction() carries: a body going nowhere and asking for
	# nothing returns ZERO, and a zero approach is refused below.
	if c.check_for_wall_climb and player.probes != null \
			and player.move_manager.can_enter(WALL_CLIMB):
		var heading_at: Vector3 = player.approach_direction()
		var ahead: Dictionary = Probes.NO_WALL_AHEAD if heading_at == Vector3.ZERO \
			else player.probes.wall_ahead_query(heading_at)
		if ahead["valid"] and ahead["tall_enough"] \
				and float(ahead["incidence"]) <= config.wall_climb.vertical_start_angle:
			return WALL_CLIMB

	if c.check_for_wall_climb and player.probes != null \
			and player.horizontal_speed() >= config.wall_run.wall_running_min_speed:
		var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
		var wall: Dictionary = player.probes.wall_query(heading)
		# TWO COOLDOWNS, DELIBERATELY, ANSWERING DIFFERENT QUESTIONS.
		#
		# can_enter() is [ME:CONFIRMED 04 §4.1] redo_move_time (0.15 s) and
		# is blind to WHICH wall: it is the short guard against a run
		# flickering off and back on within a few ticks. DO NOT let this
		# cooldown alone stand in for the same-wall refusal below -- on its
		# own it also blocks re-entry onto a wall the player never left, which
		# reads as the game refusing a run it should allow, while the
		# same-wall chain it is not built to catch stays reachable through it.
		#
		# The geometric rule that IS about which wall lives a few lines down,
		# in recent_wall_refuses_run(). Keeping them apart is what lets the
		# short one stay short.
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
			# THE WALL YOU JUST LEFT WILL NOT TAKE YOU BACK. Kicking off a
			# wall sends the body away from it, so a second run on the same
			# side of a wall facing the same way is not a rule being enforced,
			# it is arithmetic -- see Player.recent_wall_refuses_run(). Two
			# walls facing EACH OTHER stay legal, which is the zig-zag
			# corridor, and so does a wall angled away from the one just left.
			var refused: bool = player.recent_wall_refuses_run(wall["normal"], int(wall["side"]))
			if qualifies and not refused:
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
		# Cleared before the question is asked: _vault_speed_z() only ever sets
		# it, so a stale true from a tick that did not go on to vault would
		# otherwise make the next vault look like a scramble.
		player.pending_vault_rescue = false
		var hit: Dictionary = player.probes.vault_query()
		if hit["valid"] and not player.recent_wall_refuses_climb_onto(hit["edge"]):
			var variant: Dictionary = config.speed_vault.pick_variant(
				hit["height"], hit["vault_over"], _vault_speed_z(),
				player.horizontal_speed())
			# ALREADY TOUCHING NEEDS NO LEAD TIME.
			#
			# should_commit() asks whether the obstacle will be reached within
			# MaxDistanceTime at the current speed -- a question about an
			# APPROACH, and one that divides by horizontal speed. A wall climb
			# has none: the climb's own friction has taken it, and the body is
			# going straight up against a surface it is already in contact with.
			# So the gate refuses every vault out of a climb, which leaves a
			# hole: a 3.5 m wall where the climb tops out with the edge 1.7 m
			# above the feet is too LOW for a grab (min_wall_height is 1.8)
			# and unreachable by a vault that will not commit -- nothing
			# fires and the player slides back down.
			#
			# Contact is the other way of satisfying the same question, and it
			# satisfies it completely. See docs/contact-drives-movement.md.
			#
			# BUT ONLY WHILE THE BODY IS STILL GOING UP. Read the paragraph
			# above again: every word of it is about a CLIMB topping out --
			# the body is going straight up against a surface it is already
			# in contact with. A body that is merely RESTING against a wall
			# satisfies touching() just as completely and is going nowhere,
			# so DO NOT drop the rising check below: without it the bypass
			# fires forever:
			#
			#   Walking -> Falling -> SpeedVault -> Walking -> Falling -> ...
			#
			# at about forty times a second, for any body at rest pressed
			# against a face at h 0.00 v 0.00 -- for example beside a block
			# after a grab, or backing slowly off a roof edge until it drops.
			# Neither case is climbing.
			#
			# THE VAULT IS NOT WHAT LOOPS. A vault fired from a standstill has
			# no speed to carry the body anywhere, so it ends where it began,
			# hands back to Walking, falls, and meets the same open bypass on
			# the next tick. Any gate that cannot be satisfied twice from the
			# same spot would do; requiring the rise is the one that gives the
			# bypass back exactly the case it was written for.
			var rising: bool = player.velocity.y > 0.0
			var closing: bool = config.speed_vault.should_commit( 				hit["distance"], player.horizontal_speed(), variant)
			# NOWHERE TO PASS THROUGH IS NOT A VAULT. Unlike a grab, which can
			# still hang on a capped ledge, a vault has no half-measure: every
			# one of them carries the body through the space above the obstacle,
			# whether it lands there or beyond. DO NOT vault into a slab over
			# the top -- the body clips straight through it.
			var room: bool = player.fits_standing_at(hit["top"])
			if room and (closing or (rising and touching(hit.get("face_point", Vector3.ZERO)))):
				player.pending_vault_variant = variant
				return SPEED_VAULT

	# Checked before this tick's own move_and_slide(), same as the vault check
	# just above: if it fires, this move hands off to GrabMove (which
	# drives the body directly, see its own note) without this tick's physics
	# ever having moved the body at all. can_enter() enforces GrabConfig's own
	# redo_move_time (0.45 s) -- it replaces Player.can_grab_ledge(), the last
	# of the three hand-rolled cooldowns Player used to carry -- so dropping
	# off a ledge cannot instantly re-grab the very same one.
	# [ME:CONFIRMED] INTO_GRAB, not GRAB. The original reaches for a ledge
	# before hanging from it (TdMove_IntoGrab), which is what carries the body
	# to the same hanging pose however it was caught. The cooldown is still
	# checked against GRAB, since that is the move being re-entered and where
	# redo_move_time lives.
	# [ME:CONFIRMED 05 §5.6.5] The cable is caught before any ledge is
	# considered: it is an INTEREST POINT the level author placed on purpose,
	# and a probe that happened to see a ledge nearby has no such claim.
	# [ME:CONFIRMED] Falling faster than fall_limit the hands cannot hold on
	# (ZVelocityFallLimit).
	if c.check_for_zipline and player.velocity.y > -config.zipline.fall_limit \
			and player.move_manager.can_enter(ZIPLINE):
		var cable: InterestLine = player.nearest_interest_line(InterestLine.Kind.ZIPLINE)
		if cable != null and player.line_ready(cable) \
				and _zipline_approach_allowed(cable):
			return ZIPLINE

	# The bar, after the cable: same interest-point reasoning, but NO fall
	# limit. [ME:CONFIRMED A1] TdMove_Swing carries no ZVelocityFallLimit --
	# only the zipline's entry does -- and the Stormdrain rooftop is built on
	# catching a bar 5 m down, at about 13 m/s.
	if c.check_for_swing and player.move_manager.can_enter(SWING):
		var bar: InterestLine = player.nearest_interest_line(InterestLine.Kind.SWING)
		if bar != null and player.line_ready(bar):
			return SWING

	# The ladder, after the bar: same interest-point reasoning, PLUS the
	# frontal fan -- DO NOT let a ladder catch from any side but the front;
	# catch_gate() enforces it. Asked here, before ever transitioning, so
	# LadderMove.enter()'s own copy of this same check (see its note) never
	# actually fires in play.
	#
	# NO fall_limit HERE, unlike the cable and the bar above. Those two carry
	# the original's own ZVelocityFallLimit; the ladder never had one, and the
	# 6 m/s it used to borrow from them is 1.125 m of free fall at gravity 16
	# -- it refused every drop worth catching. [ME:CONFIRMED] a ladder CAN be
	# caught mid-fall, and a catch past hard_landing_height costs the same
	# lockout a hard landing does, red screen and all, rather than being
	# refused (LadderMove.enter() arms it). DO NOT restore a speed gate
	# here: the window's real ceiling is falling_uncontrolled_height, already
	# enforced by FallUncontrolledConfig leaving check_for_ladder clear, so a
	# fall that has gone uncontrolled still catches nothing.
	if c.check_for_ladder and player.move_manager.can_enter(LADDER):
		var rail: InterestLine = player.nearest_interest_line(InterestLine.Kind.LADDER)
		if rail != null and LadderMove.catch_gate(player, rail):
			return LADDER

	# A ledge, same interest-point reasoning: catch_gate() is the single
	# question every entry site asks, so jumping onto a ledge and falling
	# onto one both get answered identically to walking onto one.
	if c.check_for_ledge_walk and player.move_manager.can_enter(LEDGE_WALK):
		var ledge: InterestLine = player.nearest_interest_line(InterestLine.Kind.LEDGE_WALK)
		if ledge != null and LedgeWalkMove.catch_gate(
				player, ledge, config.ledge_walk.foot_snap_height):
			return LEDGE_WALK

	# A beam, same interest-point reasoning: catch_gate() is the single
	# question every entry site asks, so jumping onto a beam and falling onto
	# one both get answered identically to walking onto one.
	if c.check_for_balance and player.move_manager.can_enter(BALANCE):
		var beam: InterestLine = player.nearest_interest_line(InterestLine.Kind.BALANCE)
		if beam != null and BalanceMove.catch_gate(
				player, beam, config.balance.foot_snap_height):
			return BALANCE

	if c.check_for_grab and player.probes != null and player.move_manager.can_enter(GRAB):
		var ledge: Dictionary = player.probes.ledge_query()
		# The REACH's own range is checked here rather than inside it. Checked
		# there, a ledge that is visible but too far away sends the body into
		# IntoGrab, which gives up on its first tick and returns to Falling,
		# which sees the same ledge again -- an endless Falling/IntoGrab
		# flutter for as long as the ledge stays in view.
		# ...and it will not let you climb onto its own top either. Same
		# arithmetic as the wall-run refusal above: your legs are pushing off
		# that wall, so the body cannot be sent to the side it is on. This is
		# what stops a wall run from ending in a grab onto the very wall it
		# just left.
		var same_side: bool = ledge["valid"] \
			and player.recent_wall_refuses_climb_onto(ledge["edge"])
		if ledge["valid"] and _within_reach(ledge) and _can_close_the_gap(ledge) 				and not same_side:
			return INTO_GRAB

	return KEEP

## Settles the landing. Returns the state to hand off to, or KEEP while
## still airborne.
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
	# `and` short-circuits left-to-right, and the order of the three conjuncts
	# below is load-bearing. The block comes first: refusing the SKILL_ROLL
	# transition later would still let _apply_landing_cost() below charge
	# this landing as UNROLLED, keeping the roll's speed discount for a roll
	# that never happened. fall_height comes before consume_roll(), not
	# after: with consume_roll() on the left it would ALWAYS spend the
	# buffered press -- even on a landing nowhere near the roll threshold --
	# eating a crouch meant for the slide-entry check in walking_move.gd on
	# the very next tick. Keeping both ahead of consume_roll() means an
	# ordinary landing, and a blocked one, both leave the buffer untouched.
	var rolled: bool = not player.statuses.is_move_blocked(SKILL_ROLL) \
		and fall_height >= config.pawn.skill_roll_landing_height \
		and player.consume_roll()
	player.last_landing_rolled = rolled
	player.last_landing_fall_height = fall_height
	player.set_grounded(true)
	player.notify_landed(impact_speed)
	_apply_landing_cost(fall_height, rolled)
	var hurt: float = landing_damage(fall_height, rolled)
	if hurt > 0.0:
		player.take_damage(hurt, Health.Cause.HARD_LANDING)
	return landing_destination(fall_height, rolled)

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

## Whether a ledge is close enough to reach for, horizontally.
##
## [ME:CONFIRMED] ledge_find_distance is 3.5 m -- how far the probe may LOOK,
## not how far the body may be hauled. Reaching from that range reads as a
## magnet -- jump vaguely wallward and get pulled in across open air -- so
## DO NOT widen the reach to match it; the reach is held to its own, much
## shorter range. See IntoGrabConfig.max_reach_distance.
## Whether a reach at this ledge could ever make CONTACT, which is a different
## question from _within_reach() above and the one that was missing.
##
## The approach phase moves the body not at all -- it flies its own arc and the
## reach waits to see whether the hands arrive (docs/contact-drives-movement.md).
## So a body with no horizontal travel toward the face keeps exactly the gap it
## started with, and if that gap is wider than contact_reach() the hands never
## arrive: the reach burns its whole max_duration, hands back to Falling, waits
## out redo_move_time, and commits again on a ledge that has not moved. Nothing
## about the situation changes, so the loop does not end -- and the player has
## no control for the 1.5 s of each pass, which is a soft lock rather than a
## flutter.
##
## Reported at 0.8 m of commit range against 0.48 m of contact range, so any
## ledge in that band locked the player up. Standing 0.8 m out and jumping
## straight up did it; so did standing flush and looking 34 degrees off square,
## because the probe measures along the LOOK direction and turning the view
## lengthens the same gap.
##
## DO NOT fix this by shrinking max_reach_distance to the contact range. The
## wider commit is right for the case it was written for: a body flying AT a
## wall closes the gap on its own within a tick or two, and refusing it at
## 0.8 m would take away the ordinary running grab. What is wrong is committing
## when nothing will close the gap.
##
## Asked every tick rather than once at take-off, so a jump straight up
## followed by air control toward the wall still commits the moment the body
## starts going there.
func _can_close_the_gap(ledge: Dictionary) -> bool:
	return closing_on(ledge.get("face_point", Vector3.ZERO))

func _within_reach(ledge: Dictionary) -> bool:
	# Measured to the WALL, not to the edge point. `edge` is on the ledge's
	# top, found by dropping a probe past the face, so against anything with
	# depth it sits well behind the surface the body would touch -- 1.78 m for
	# a 1 m deep block whose face was only 0.9 m away.
	return float(ledge.get("face_distance", INF)) <= config.into_grab.max_reach_distance

## Whether the body's approach is compatible with the direction this cable
## would carry it. DO NOT let a jump against the cable's travel direction
## catch it.
##
## Vertical-jump carve-out first: below a stillness threshold the approach
## HAS no direction, and boarding from directly underneath stays legal. The
## angle cap itself is ZiplineConfig.catch_max_approach_angle -- see its own
## note on why 100 degrees and why it is a dial.
func _zipline_approach_allowed(cable: InterestLine) -> bool:
	var h_vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	# Below this the jump is vertical and has no meaningful approach direction.
	if h_vel.length() <= 0.5:
		return true
	var travel: Vector3 = ZiplineMove.travel_direction(cable, player.global_position)
	travel.y = 0.0
	if travel.length_squared() < 0.0001:
		# A near-vertical cable has no horizontal travel to oppose.
		return true
	return rad_to_deg(h_vel.angle_to(travel)) <= config.zipline.catch_max_approach_angle

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
	return WALKING

## [ME:CONFIRMED] Landing bleeds horizontal speed according to which of four
## tiers the ACCUMULATED FALL HEIGHT falls into -- never according to this
## frame's vertical speed. See Player.landing_keep_ratio().
func _apply_landing_cost(fall_height: float, rolled: bool) -> void:
	var keep: float = player.landing_keep_ratio(fall_height, rolled)
	player.velocity.x *= keep
	player.velocity.z *= keep
	if keep <= 0.0:
		# DO NOT zero only the velocity here -- the BUDGET must drop too.
		# [ME:CONFIRMED] After a hard landing in the original, getting going
		# again is indistinguishable from starting cold; leaving the energy
		# that buys speed full while zeroing speed itself means the ceiling is
		# still up there, so one stride puts the player back at pace and a
		# hard landing costs nothing.
		player.speed_energy.reset()
	else:
		# [ME:CONFIRMED] A landing that keeps its speed (this branch)
		# re-derives the ground budget from the speed the body actually lands
		# with, so a fast zipline exit grounds into a full sprint rather than
		# decaying back to the pre-ride pace.
		player.speed_energy.restore_for_landing(player.horizontal_speed())

## The vertical speed the vault table is asked about, which is the REAL one
## except inside the shin-catch window below.
##
## A DELIBERATE DIVERGENCE FROM THE ORIGINAL. [ME:CONFIRMED] Five of the six
## rows in SpeedVaultConfig.variants require MinSpeedZ >= 0 -- they only
## match while RISING -- and the sixth, auto_step_up_right_leg, is the
## descending one but tops out at 0.48 m and 3 m/s. So falling onto a
## metre-high ledge at running pace matches NOTHING in the original, and the
## only way to vault it is to catch the rising half of a jump, which leaves
## too narrow a window to use in practice.
##
## [ME:INFERRED 05 §5.7] autostepuprightleg is a RESCUE in the original, not
## a move: the player jumps a gap and falls short, their shin catches the far
## edge, and the game kicks them up in the last 0.2 s. This function widens
## that rescue rather than reproducing it, and it is worth knowing which is
## which if the two are ever compared.
##
## Three gates, so it stays a rescue rather than becoming a second way to play:
##
##   * FALLING, not rising. A rising body is already covered by the real rows.
##   * SHORT OF A HARD LANDING. hard_landing_height is the same 5.3 m that
##     decides whether a landing costs two seconds, reused rather than given a
##     knob of its own: a fall that is about to hurt is not one to rescue.
##   * ASKING FOR IT. The player has to be pushing INTO the obstacle. Falling
##     past a ledge with no input is a fall, and turning it into a vault would
##     be the game playing itself.
##
## Reported as a level speed rather than as a flag, which keeps
## SpeedVaultConfig.variants a pure transcription of the original's table: the
## high tiers ask for MinSpeedZ 0.5 and still refuse, so a genuinely high vault
## still costs a jump. Only the middle tier is rescued.
func _vault_speed_z() -> float:
	var speed_z: float = player.velocity.y
	if speed_z >= 0.0:
		return speed_z
	if player.fall_tracker == null:
		return speed_z
	if player.fall_tracker.fall_height >= config.pawn.hard_landing_height:
		return speed_z
	# player.last_input rather than a parameter: probe_transition() takes none,
	# and this is the same field CharacterAnimator reads for the same reason.
	if player.last_input == null:
		return speed_z
	var wish: Vector3 = player.wish_direction(player.last_input)
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if wish.length_squared() < 0.0001 or facing.length_squared() < 0.0001:
		return speed_z
	if wish.normalized().dot(facing.normalized()) <= 0.0:
		return speed_z
	# Recorded, because it changes what the vault LOOKS like. A rescued vault
	# was not set up -- there was no run-up and no plant, the player simply
	# arrived -- so CharacterAnimator plays a step-up rather than the
	# hand-planted SafetyVault. See SpeedVaultMove.is_scramble().
	player.pending_vault_rescue = true
	return 0.0

