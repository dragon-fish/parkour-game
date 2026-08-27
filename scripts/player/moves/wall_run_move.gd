class_name WallRunMove
extends Move

# Wall running is physics-driven, unlike the scripted vault and mantle: the
# player keeps real velocity and real collisions, gravity is merely weakened
# and a push is applied along the wall.

## Shape returned by _query_wall() when there is no probe to ask, matching
## Probes.wall_query()'s own "nothing found" shape.
const _NO_WALL := {"valid": false, "normal": Vector3.ZERO, "side": 0, "incidence": 0.0}

var _normal: Vector3 = Vector3.ZERO
var _along: Vector3 = Vector3.ZERO
## Set in enter() when the wall query comes back invalid: there is nothing to
## run along, so physics_update() hands straight back to Falling without ever
## touching velocity. See enter()'s note.
var _aborted: bool = false
## Seconds since this attach began. The wall jump's entire execution gradient
## reads this and nothing else (see wall_jump_quality).
var _time_on_wall: float = 0.0
## Whether the look fan has been re-centred on the WALL yet. Deferred to the
## first physics tick rather than done in enter(); see _recentre_on_wall().
var _fan_centred: bool = false
## The fan's centre, EASED toward the wall's own line rather than snapped to it.
## A blockout curve is a row of straight segments, so the normal arrives in
## steps of several degrees at each seam; followed rigidly, every seam is a
## visible tick in the view.
var _fan_yaw: float = 0.0
## Space pressed while Q's sweep is still carrying the view round. HELD, not
## acted on: see the note where it is armed.
var _kick_armed: bool = false
## Q pressed before there was a fan to sweep across. Spent as soon as there is.
var _turn_armed: bool = false

## Guarded the same way SpeedVaultMove/GrabMove guard their own probe
## lookups: `player.probes` is null-checked at every call site rather than
## dereferenced directly, so this move degrades the same way its siblings do
## for a hand-built player with no probe rig, instead of crashing.
func _query_wall() -> Dictionary:
	if player.probes == null:
		# .duplicate(), never the const itself: see probes.gd's own NO_HIT note
		# -- a const Dictionary is read-only, and returning the shared instance
		# directly would hand every caller the same read-only object.
		return _NO_WALL.duplicate()
	# ONCE A RUN HAS A WALL, IT TRACKS THAT WALL AND NOT THE BODY'S SIDES.
	#
	# DO NOT let wall_query()'s rigidly local rays -- straight out to left and
	# right -- drive tracking after attach: turning the view during a run would
	# swing them off the wall and end the run the moment the player stops
	# looking forward. [ME:CONFIRMED] The original does not do that: the body
	# completes the wall-run curve wherever the player is looking, and looking
	# around is most of what the run is FOR, since the jump off it steers by
	# the view.
	#
	# Entry still goes through wall_query(), where local rays are right: a
	# player who has not attached yet is facing roughly the way they are going,
	# and there is no known normal to track.
	if _normal != Vector3.ZERO:
		return player.probes.wall_tracked_query(-_normal, \
			config.wall_run.wall_running_forward_check_distance)
	var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	return player.probes.wall_query(heading)

## Recomputes _along from the CURRENT _normal and the player's CURRENT
## horizontal velocity. Called every time _normal is (re)assigned -- once in
## enter(), and again every tick in physics_update() -- so the tangent tracks
## the true wall surface instead of the angle it happened to have on attach.
##
## THIS IS WHAT MAKES CURVED WALLS WORK. Together with wall_tracked_query()
## following the wall by its normal rather than by the body's sides, it means a
## run laid along an arc simply keeps turning with the surface. [ME:CONFIRMED]
## The original does the same: a run laid along an inward-curving arc keeps
## turning with the surface instead of running off it straight.
##
## DO NOT cache the tangent at attach. It would look like a harmless tidy-up --
## the normal barely changes on a flat wall, which is every wall in the test
## arena -- and it would flatten every curve in the game back into a straight
## line. tests/test_wall_run_look.gd holds a curved fixture for exactly this.
func _derive_along() -> void:
	var tangent: Vector3 = _normal.cross(Vector3.UP).normalized()
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_along = tangent if tangent.dot(horizontal) >= 0.0 else -tangent

## Yaw that faces along the wall, in the direction of travel.
##
## THE FAN BELONGS TO THE WALL, NOT TO HOW YOU ARRIVED AT IT. Left to
## set_look_constraint's own capture, the fan is centred on whatever the body
## happened to be facing when it attached -- and [ME:CONFIRMED 04 §4.1] the
## forward branch admits approaches up to 57 degrees off the wall's line, so
## "look 90 degrees away" meant something different on every attach. Exactly
## the mistake the ledge hang made first, for exactly the same reason.
##
## Derived from _along, which is derived from the wall's own normal, so what
## the fan is pinned to is the wall's geometry and nothing about the player.
func _along_yaw() -> float:
	# Body forward is -Z: rotating (0, 0, -1) by yaw gives (-sin, 0, -cos), so
	# facing direction d means yaw = atan2(-d.x, -d.z).
	return atan2(-_along.x, -_along.z)

## Called once, on the first PHYSICS tick rather than in enter().
##
## Order is the reason: MoveManager pushes the look constraint AFTER the move's
## enter() returns, and that push captures the reference itself whenever no
## constraint was in force -- which is the case coming from Jump. A re-centre
## done in enter() is overwritten a few microseconds later by the very call
## that turns the fan on.
func _recentre_on_wall() -> void:
	if _fan_centred or player.camera_rig == null:
		return
	_fan_centred = true
	_fan_yaw = _along_yaw()
	player.camera_rig.recentre_yaw_reference(_fan_yaw)

## Carries the fan -- and, partly, the view -- round with a wall that turns.
##
## The fan is measured against the wall's own line, so on a curve it has to
## turn with it, or it ends up policing a direction the wall stopped pointing
## in metres ago: when the wall's normal changes, the view gets an assisted
## turn, and the clamp has to move with it.
##
## The clamp always travels the FULL turn; only the view is partial, by
## view_assist. See CameraRig.shift_yaw_reference() for how the two are
## separated without re-deriving the yaw accumulator.
func _track_fan_to_wall(delta: float) -> void:
	if not _fan_centred or player.camera_rig == null:
		return
	var target: float = _along_yaw()
	var difference: float = wrapf(target - _fan_yaw, -PI, PI)
	# A DISCONTINUITY, not a curve. _along picks its sign from the direction of
	# travel, so a body whose along-wall velocity momentarily reverses reports a
	# tangent half a turn away. Carrying the view through that would be a
	# catastrophe rather than an assist; re-seat and carry nothing.
	if absf(difference) > PI * 0.5:
		_fan_yaw = target
		player.camera_rig.shift_yaw_reference(_fan_yaw, 0.0)
		return
	_fan_yaw += difference * clampf(config.wall_run.fan_track_speed * delta, 0.0, 1.0)
	player.camera_rig.shift_yaw_reference(_fan_yaw, config.wall_run.view_assist)

func enter(_previous: StringName) -> void:
	_time_on_wall = 0.0
	_aborted = false
	_fan_centred = false
	_kick_armed = false
	_turn_armed = false
	# Wall running IS physics-driven, but grounded-ness is still DECLARED, never
	# inferred -- P2 replaced is_on_floor() as the authority precisely so that
	# no move can leave a stale value behind. This first declaration covers
	# THIS tick only (the tick FallingMove handed off without ever calling
	# move_and_slide()); every subsequent tick's physics_update() below
	# declares again from that tick's own move_and_slide() result. See the
	# CRITICAL note there for why a single declaration here would not be
	# enough.
	player.set_grounded(false)

	# FallingMove already null-checks player.probes AND requires a valid
	# wall_query() before ever transitioning here, so this branch is not
	# reachable in normal play. Kept as a genuinely safe guard for a future
	# caller that skips that gate, mirroring SpeedVaultMove's/GrabMove's own
	# _aborted pattern: a zero normal would give _derive_along() a zero
	# tangent (no push direction at all) -- there is no safe wall to attach
	# to when the probe found nothing, so attach to none and let the player
	# fall.
	var query: Dictionary = _query_wall()
	if not query["valid"]:
		_aborted = true
		return
	_normal = query["normal"]
	# FIXED FOR THE WHOLE RUN. Not refreshed from the per-tick tracking query
	# below, which deliberately reports no side at all -- see
	# Probes.wall_tracked_query()'s own note. Which side the wall is on is a
	# fact about this run, not about where the player is looking this tick, and
	# a side that follows the view flips the look fan out from under the view
	# mid-turn and clamps it straight back to centre.
	player.wall_side = int(query["side"])
	player.note_wall_contact(_normal, player.wall_side)

	# Run along the wall in whichever of the two tangent directions the player
	# is already moving. A wall never reverses you.
	_derive_along()

	# Kill any velocity going INTO the wall, or the body grinds against it.
	# `player` is deliberately untyped (see Move), so `player.velocity`
	# arrives as Variant and `:=` cannot infer a type from it -- annotate
	# explicitly, matching the pattern SlideMove already uses for the same
	# reason.
	var into: float = player.velocity.dot(_normal)
	if into < 0.0:
		player.velocity -= _normal * into

	# One-off lift on attaching, read as a one-off vertical boost rather than a
	# sustained force: WallRunningHorisontalInitialZHeight is stored as a
	# HEIGHT (170 uu / 1.7 m), converted here at the point of use into the
	# vertical speed that reaches that height, matching how this project reads
	# every other `*ZHeight` field (spec §2.5). DO NOT convert it against plain
	# gravity the way those others do: the rise happens WHILE ATTACHED, where
	# gravity is already weakened by wall_gravity_scale (applied a few lines
	# below, every tick this move is active), and plain config.pawn.gravity
	# asks "how fast to reach 1.7 m under gravity this move never actually
	# uses" -- overshooting the real rise by 1 / wall_gravity_scale (a factor
	# of ~2.86x at the default 0.35: plain gravity gives 5.2154 m/s and an
	# actual ~4.86 m rise, where the wall run's own effective gravity gives
	# 3.0854 m/s and the intended 1.7 m).
	#
	# [ME:CONFIRMED 04 §4.1] The rise is measured FROM THE GROUND YOU LEFT, not
	# added to wherever contact happened: standing at Z 43.17 and peaking at ZT
	# 44.82 (SZD 1.56), a wall run tops out about 1.65 m above the roof it took
	# off from, regardless of where on the wall contact happened -- that height
	# is InitialZHeight.
	#
	# DO NOT add the lift to the contact point instead of the ground: contact
	# height rises with speed, so a contact-relative lift makes a fast run's
	# peak rise with it too, putting the FEET above the plank top at speed
	# where the confirmed peak keeps the WAIST level with it.
	var lift: float = config.wall_run.wall_running_horisontal_initial_z_height
	if lift > 0.0:
		var risen: float = player.global_position.y - player.ground_reference_y
		var remaining: float = clampf(lift - risen, 0.0, lift)
		# The lift is a RISE, so it converts against the rising scale.
		var wall_gravity: float = config.pawn.gravity * config.wall_run.wall_gravity_scale_rising
		# [ME:CONFIRMED 04 §4.1] ASSIGNED, not maxf(): a body arriving faster
		# than the target must be SLOWED to it, not merely floored at it, or the
		# peak goes back to depending on entry speed -- the measured entry
		# window reaches +5.1 m/s of rise and the peak still holds at 1.65 m
		# regardless.
		player.velocity.y = sqrt(2.0 * wall_gravity * remaining)

func exit() -> void:
	player.wall_side = 0
	# Cleared so the NEXT run's entry goes back through wall_query()'s local
	# rays. Left set, _query_wall() would try to track a wall this run has
	# already left, from a body that may be nowhere near it.
	_normal = Vector3.ZERO
	# No same-wall reattach cooldown to clear here: MoveManager's generic
	# redo_move_time covers it, arming itself the moment this move exits --
	# see MoveManager.can_enter()'s own note on replacing the hand-rolled wall
	# reattach window.

## How early the jump came: 1 (kicked the instant the wall was touched) to 0
## (rode the run out).
##
## [ME:CONFIRMED 04 §4.4] Replaces a facing-based reading. [ME:COMMUNITY] The
## instruction this gradient was originally modelled on -- face the wall you
## are running on, then jump, for noticeably more speed -- turned out not to
## be what the game measures: across 24 kick-offs the correlation between
## speed gained and view rotation during the run was -0.19, while the
## correlation with time on the wall was -0.42, and the fast/slow medians
## differ 6x.
##
## Facing is not disproven as a SECONDARY term -- both measured takes held the
## mouse fairly still -- but it is not the primary one, and timing alone
## reproduces the observed spread.
static func wall_jump_quality(time_on_wall: float, cfg: WallrunJumpConfig) -> float:
	if time_on_wall <= cfg.wall_jump_prime_window:
		return 1.0
	if time_on_wall >= cfg.wall_jump_stale_time:
		return 0.0
	return 1.0 - clampf(inverse_lerp(cfg.wall_jump_prime_window, \
		cfg.wall_jump_stale_time, time_on_wall), 0.0, 1.0)

## Where the kick actually points. [ME:INFERRED] The VIEW steers it -- Faith
## leaves in the direction the camera faces -- with a floor on the
## away-from-wall component so that looking into the wall still leaves it.
## Falls back to the bare normal when there is no usable facing.
static func wall_jump_push_direction(player_body: Node3D, normal: Vector3, 		cfg: WallrunJumpConfig) -> Vector3:
	var facing: Vector3 = -player_body.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return normal
	var dir: Vector3 = facing.normalized()
	var away: float = dir.dot(normal)
	if away >= cfg.wall_jump_min_away:
		return dir
	# Rotate the aim toward the normal by exactly enough to clear the floor,
	# rather than discarding it: the remaining view component is what makes
	# the kick aimable at all.
	return (dir + normal * (cfg.wall_jump_min_away - away)).normalized()

## The horizontal velocity a kick leaves with: the speed already in the body,
## TURNED toward where the player is looking, plus the push on top.
##
## Turning rather than merely adding is the correction: DO NOT just add the
## push to the carried velocity. Added to a body still carrying 7 m/s along
## the wall, a sideways push of a few m/s barely bends the path, leaving a
## player unable to jump out sideways at all. The run builds the speed; the
## kick decides where it goes.
##
## Interpolated between the two directions rather than rotated, so a hard turn
## arrives slightly slower than a soft one. That is the same tax this project
## charges for turning everywhere else, and it falls out for free here.
static func wall_jump_launch(player_body: Node3D, carried_velocity: Vector3, 		normal: Vector3, time_on_wall: float, cfg: WallrunJumpConfig) -> Vector3:
	# Taken as an argument rather than read off the body, matching
	# wall_jump_push_direction() above: the body is here for its FACING, and a
	# static helper that quietly requires its Node3D to also be a
	# CharacterBody3D is a helper nothing can test in isolation.
	var carried := Vector3(carried_velocity.x, 0.0, carried_velocity.z)
	var direction: Vector3 = wall_jump_push_direction(player_body, normal, cfg)
	var speed: float = carried.length()
	var turned: Vector3 = carried.lerp(direction * speed, clampf(cfg.look_redirect, 0.0, 1.0))
	return turned + direction * wall_jump_push_away(time_on_wall, cfg)

static func wall_jump_push_away(time_on_wall: float, cfg: WallrunJumpConfig) -> float:
	var quality := wall_jump_quality(time_on_wall, cfg)
	return cfg.wall_running_push_away_speed_noob \
		+ cfg.wall_running_push_away_speed_pro_add * quality

## The rise is stored as a HEIGHT in the original (spec §2.5's `*ZHeight`
## convention), converted here at the point of use. Unlike the attach-time
## lift in enter() above, this rise happens AFTER the player leaves the wall
## -- the jump branch below hands off to Jump the same tick -- so plain
## gravity applies, not wall_gravity_scale (that scale only governs ticks this
## move itself advances while still attached; see enter()'s own note on the
## exact overshoot that conflating the two produces).
static func wall_jump_rise_velocity(time_on_wall: float, \
		cfg: WallrunJumpConfig, pawn: PawnConfig) -> float:
	var quality := wall_jump_quality(time_on_wall, cfg)
	var height: float = cfg.wall_running_jump_off_z_height_forward \
		+ cfg.wall_running_jump_off_z_height_max_add_turned * quality
	# JumpOffZHeight is a height, not a speed -- convert at the point of use.
	return sqrt(2.0 * maxf(pawn.gravity, 0.001) * maxf(height, 0.0))

## The edge of the yaw fan that points away from the wall, in the fan's own
## coordinates. Positive for a wall on the left, negative for one on the right,
## matching MoveManager's own mirroring of the declared fan.
func _away_edge() -> float:
	# The declared fan is the LEFT wall's, which is the negative half (yaw grows
	# leftward, and a left wall is turned away from to the right), so its span
	# is the magnitude of the minimum. A right-hand wall gets the positive half.
	var span: float = absf(config.wall_run.min_look_constraint.y)
	return span if player.wall_side > 0 else -span

func physics_update(delta: float, input: MoveInput) -> StringName:
	# Q HERE MOVES THE VIEW, NOT THE BODY. Everywhere else it starts a turn; on
	# a wall the body is already committed to the wall's own curve and nothing
	# about it should change. What Q saves is the mouse flick: it must drive
	# exactly the value the mouse drives, and the mouse takes it back the
	# instant the player touches it -- turning 90 degrees right by hand and
	# pressing space has to feel the same as pressing Q and space.
	#
	# Swept to the fan's far edge, which the wall's side already decides: the
	# fan runs from straight-ahead to a quarter turn AWAY from the wall, so its
	# far edge IS the direction a kick should leave in.
	# BUFFERED, AND HELD UNTIL THE FAN EXISTS.
	#
	# DO NOT read the press directly: pressing Q in the first ten frames of a
	# run would turn the view only a few degrees. Two causes, both about ORDER.
	# The fan is not centred on the wall until this move's first physics tick
	# (see _recentre_on_wall()), and re-centring WRITES _look_relative_yaw --
	# so a sweep armed before that has its remaining distance rewritten out
	# from under it and finishes almost at once. And a press that arrives even
	# earlier, while the run is still being entered, had nowhere to go at all.
	#
	# So the press is stored rather than read, and spent on the first tick
	# there is a wall-centred fan to sweep across. Same mechanism as the jump
	# buffer, for the same reason: the player pressed when it FELT right, and
	# the game was a few frames from being able to honour it.
	if player.consume_buffered_turn():
		_turn_armed = true
	if _turn_armed and _fan_centred and player.camera_rig != null:
		_turn_armed = false
		player.camera_rig.sweep_look_to(_away_edge())

	# Advanced before anything else can read it, so a jump taken on this tick
	# is priced by the time already spent on the wall rather than by the time
	# spent before this tick began.
	_time_on_wall += delta

	# THE LADDER can catch a wall run mid-attach: a level built on running
	# straight into a pipe or ladder has to actually catch. WallRunMove asks
	# the same frontal gate the ground and the air do, no check_for_ladder
	# switch involved (that flag is airborne-only). Checked
	# even on an ABORTED tick: a body that failed to find a wall this tick may
	# still be sitting inside a ladder's own front volume, and the ladder
	# should not lose to a wall that was never really there.
	if player.move_manager.can_enter(LADDER):
		var rail: InterestLine = player.nearest_interest_line(InterestLine.Kind.LADDER)
		if rail != null and LadderMove.catch_gate(player, rail):
			return LADDER

	if _aborted:
		return FALLING

	# Refresh the wall's geometry EVERY tick from a fresh query, not just
	# once at entry. IMPORTANT (review): _normal used to be captured once in
	# enter() and never refreshed, even though a query was already being made
	# every tick to check validity. On a curved or angled wall that meant (a)
	# the jump push and stick force kept pointing along the STALE entry
	# normal, and (b) _along drifted off the true tangent and bled speed into
	# the wall. Reusing the query already being paid for here (rather than
	# adding a second one) fixes both at once: everything below this point
	# reads the CURRENT surface.
	var query: Dictionary = _query_wall()
	if not query["valid"]:
		return FALLING
	_normal = query["normal"]
	_derive_along()
	# Refreshed every tick, so the lockout it arms is measured from when the
	# wall is LEFT rather than from when it was found. See Player's own note.
	player.note_wall_contact(_normal, player.wall_side)
	_recentre_on_wall()
	_track_fan_to_wall(delta)

	# A wall jump is a fresh press, not a ground-style coyote jump: the
	# jump/coyote timer only refills while player.grounded is true, and this
	# move truthfully declares grounded=false every tick, so
	# player.consume_jump() is permanently dead here. But a plain
	# `_input.jump_pressed` edge check is ALSO wrong (verified, see
	# task-1-report.md): FallingMove hands off to this move's enter() the
	# moment it detects a wall, before this move's own first
	# physics_update() ever runs, so a press made on the attach tick -- or
	# any of the up-to jump_buffer_time ticks before it, exactly like every
	# other buffered jump in this game -- would land on a tick this move
	# never sees jump_pressed==true on, and get silently dropped on the most
	# timing-sensitive move there is. consume_buffered_jump() reads the same
	# buffer WalkingMove/FallingMove do, just without the coyote requirement
	# that would otherwise be impossible to satisfy here, and spends it so a
	# consumed press cannot also fire a second jump later.
	# ARMED, NOT FIRED, WHILE A SWEEP IS RUNNING.
	#
	# [ME:CONFIRMED] The original pre-buffers this: pressing Q, then space
	# before the view has come round, still makes Faith jump out the instant
	# it does. The kick steers by the view, so taking it mid-sweep launches
	# along a facing halfway to where the player asked for -- and the whole
	# reason to press Q was to choose that facing.
	#
	# Only a SWEEP defers it. A player who never pressed Q, or who took the
	# mouse back and cancelled the sweep, kicks the moment they ask.
	if player.consume_buffered_jump():
		_kick_armed = true
	var sweeping: bool = player.camera_rig != null and player.camera_rig.is_sweeping()
	if _kick_armed and not sweeping:
		# [ME:CONFIRMED 04 §4.1, §4.4] UNCONDITIONAL, matching the original 1:1:
		# no height ceiling is applied to a wall-jump chain here. The original
		# bounds a chain through each jump's own JumpOffZHeight (a bounded
		# PER-USE skill gradient) and a RedoMoveTime of only 0.15 s, not a
		# total-climb height cap.
		#
		# ACCEPTED RISK, recorded in spec §8 rather than papered over here: a
		# zig-zag chain between two close, oppositely-facing walls can climb
		# without bound. Shipped 1:1 on purpose.
		#
		# Both terms below carry the Noob-to-Pro skill gradient (04 §4.4),
		# driven by TIME ON WALL, not facing -- see wall_jump_quality() above
		# for the measurement.
		var jump_cfg: WallrunJumpConfig = config.wallrun_jump
		player.velocity.y = wall_jump_rise_velocity(_time_on_wall, jump_cfg, config.pawn)
		var launch: Vector3 = wall_jump_launch(player, player.velocity, _normal,
			_time_on_wall, jump_cfg)
		player.velocity.x = launch.x
		player.velocity.z = launch.z
		player.move_and_slide()
		# Declared even on this away-transitioning tick, mirroring
		# WalkingMove's and SlideMove's own jump branches: move_and_slide()
		# just ran, so is_on_floor() is a real answer, not a stale one, and
		# reporting it truthfully costs nothing since JumpMove's own first
		# tick will re-declare regardless.
		player.set_grounded(player.is_on_floor())
		# JUMP, not FALLING. A wall kick IS a launch -- the player pressed
		# jump and left the wall rising -- and [ME:CONFIRMED 11 §11.2] in the
		# original every one of the seven states holding bCheckForWallClimb is
		# a launch state. Handing off to Falling instead would drop the player
		# into the one airborne state whose config deliberately does NOT
		# carry check_for_wall_climb, so no further wall could be attached
		# until the next ground contact: no chained wall kicks at all, which
		# is the technique this whole move exists to serve.
		# Jump hands on to Falling by itself once the rise decays past
		# enter_to_falling_z_speed (JumpMove's own check), so nothing here
		# has to guess when the launch stops being one.
		return JUMP

	# Push along the wall's tangent UP TOWARD the energy-curve ceiling
	# (Player.speed_cap()) -- NOT a wall-specific max speed: the speed ceiling
	# is handed to the energy curve everywhere (spec §5.5), so there is no
	# separate wall_max_speed here. A player who enters already at their own
	# foot-speed ceiling gets little or nothing from this branch, matching
	# wall_running_min_speed's own invariant that a wall run CARRIES speed
	# rather than creating it.
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var along_speed := horizontal.dot(_along)
	var ceiling: float = player.speed_cap()
	if along_speed < ceiling:
		var add := minf(config.wall_run.wall_running_horisontal_acceleration * delta, ceiling - along_speed)
		player.velocity += _along * add

	# Deceleration, applied to TOTAL horizontal speed every tick regardless of
	# whether the acceleration above added anything -- THIS is the force that
	# actually ends a wall run now that there is no duration cap. Friction
	# (wall_running_horisontal_friction, 5%) barely bites on its own; this is
	# what makes a faster entry simply take longer to decay past
	# wall_running_min_speed (see the exit checks below).
	var decel: float = config.wall_run.wall_running_horisontal_deceleration * delta
	var decayed: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).move_toward(Vector3.ZERO, decel)
	player.velocity.x = decayed.x
	player.velocity.z = decayed.z

	# Weakened gravity plus a gentle pull into the wall so the body stays glued
	# through small surface irregularities.
	# Asymmetric by measurement (04 §4.1): the climb is braked at ~49% of world
	# gravity while the descent only accelerates at ~32%. Reading the sign of
	# the current velocity rather than tracking a phase keeps the apex handling
	# implicit -- the tick that crosses zero simply starts using the other one.
	var wall_gravity_scale: float = config.wall_run.wall_gravity_scale_rising 		if player.velocity.y > 0.0 else config.wall_run.wall_gravity_scale_falling
	player.velocity.y -= config.pawn.gravity * wall_gravity_scale * delta
	player.velocity -= _normal * config.wall_run.wall_stick_force

	player.move_and_slide()

	# CRITICAL: declared EVERY tick this move stays active, not just once in
	# enter(). MoveManager's invariant only checks "declared at least once
	# since entry" -- a move that declared a stale value in enter() and never
	# again would satisfy that check while lying for the rest of its run. Here
	# it is never stale: move_and_slide() just ran this tick, so is_on_floor()
	# is a fresh, true reading every time this line executes, for every branch
	# below (WALKING and FALLING alike, and the fall-through KEEP).
	player.set_grounded(player.is_on_floor())

	if player.grounded:
		return WALKING
	# No timer. The original ends a wall run by momentum alone -- friction is
	# only 0.05 but deceleration works on total horizontal speed every tick,
	# so a faster entry simply lasts longer. That is what makes speed pay off
	# on a wall. Measured as TOTAL horizontal speed (matching
	# wall_running_min_speed's own entry measurement), not projected onto
	# _along.
	if Vector2(player.velocity.x, player.velocity.z).length() < config.wall_run.wall_running_min_speed:
		return FALLING
	# Read as a vertical SINK speed -- see WallRunConfig's own note on
	# wall_running_velocity_stop_limit.
	if player.velocity.y < config.wall_run.wall_running_velocity_stop_limit:
		return FALLING
	return KEEP
