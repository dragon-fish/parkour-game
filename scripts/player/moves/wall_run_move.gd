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
	var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	return player.probes.wall_query(heading)

## Recomputes _along from the CURRENT _normal and the player's CURRENT
## horizontal velocity. Called every time _normal is (re)assigned -- once in
## enter(), and again every tick in physics_update() -- so the tangent tracks
## the true wall surface instead of the angle it happened to have on attach.
func _derive_along() -> void:
	var tangent: Vector3 = _normal.cross(Vector3.UP).normalized()
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_along = tangent if tangent.dot(horizontal) >= 0.0 else -tangent

func enter(_previous: StringName) -> void:
	_time_on_wall = 0.0
	_aborted = false
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
	player.wall_side = query["side"]

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

	# One-off lift on attaching. ⚠️ Read as a one-off vertical boost rather
	# than a sustained force: WallRunningHorisontalInitialZHeight is stored as
	# a HEIGHT (170 uu / 1.7 m), converted here at the point of use into the
	# vertical speed that reaches that height, matching how this project reads
	# every other `*ZHeight` field (spec §2.5) -- EXCEPT that this one
	# deliberately does NOT use plain gravity the way those others do. The
	# rise happens WHILE ATTACHED, where gravity is already weakened by
	# wall_gravity_scale (applied a few lines below, every tick this move is
	# active); converting against plain config.pawn.gravity instead would ask
	# "how fast to reach 1.7 m under gravity this move never actually uses",
	# overshooting the real rise by 1 / wall_gravity_scale (a factor of
	# ~2.86x at the default 0.35 -- confirmed directly: plain gravity gives
	# 5.2154 m/s and an actual ~4.86 m rise; the wall run's own effective
	# gravity gives 3.0854 m/s and the intended 1.7 m).
	# Never LOWERS an already-faster upward speed (e.g. a jump that grabbed a
	# wall mid-rise) -- only ever raises it to the floor this represents.
	var lift: float = config.wall_run.wall_running_horisontal_initial_z_height
	if lift > 0.0:
		# The lift is a RISE, so it converts against the rising scale.
		var wall_gravity: float = config.pawn.gravity * config.wall_run.wall_gravity_scale_rising
		player.velocity.y = maxf(player.velocity.y, sqrt(2.0 * wall_gravity * lift))

func exit() -> void:
	player.wall_side = 0
	# Nothing else to do here now: the same-wall reattach cooldown
	# (note_wall_detach()/can_attach_wall(), keyed to the wall's own normal)
	# is gone, a deliberate 1:1 deletion -- see falling_move.gd's own note on
	# what replaced it (MoveManager's generic redo_move_time, which arms
	# itself the moment this move exits, with no help needed here).

## How early the jump came: 1 (kicked the instant the wall was touched) to 0
## (rode the run out).
##
## ✅ MEASURED (04 §4.4), and it replaced a facing-based reading. The community
## instruction this gradient was modelled on -- "face the wall you are running
## on, then jump, and you gain noticeably more speed" -- turned out not to be
## what the game measures: across 24 kick-offs the correlation between speed
## gained and view rotation during the run was -0.19, while the correlation
## with time on the wall was -0.42, and the fast/slow medians differ 6x.
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

## Where the kick actually points. The VIEW steers it -- measured in the
## original, Faith leaves in the direction the camera faces -- with a floor on
## the away-from-wall component so that looking into the wall still leaves it.
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

func physics_update(delta: float, _input: MoveInput) -> StringName:
	# Advanced before anything else can read it, so a jump taken on this tick
	# is priced by the time already spent on the wall rather than by the time
	# spent before this tick began.
	_time_on_wall += delta

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
	player.wall_side = query["side"]
	_derive_along()

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
	if player.consume_buffered_jump():
		# UNCONDITIONAL, matching the original 1:1 -- this used to clamp the
		# rise against a height ceiling computed from player.ground_reference_y
		# (WallRunMove._height_ceiling(), ~40 lines, deleted this task). That
		# governor was this project's own invention: the original bounds a
		# wall-jump chain through each jump's own JumpOffZHeight (a bounded
		# PER-USE skill gradient, Task 12's job) and a RedoMoveTime of only
		# 0.15 s, not a total-climb height cap. ACCEPTED RISK (spec §8,
		# recorded there deliberately rather than papered over here): a
		# zig-zag chain between two close, oppositely-facing walls may now
		# climb without bound. Shipped 1:1 on purpose -- see this task's own
		# report for what automated testing could and could not show about it.
		# STILL ACCURATE, and only NOW actually reachable: for one branch's
		# worth of history this hand-off returned FALLING, which cannot climb
		# a wall at all (no check_for_wall_climb), so the risk described above
		# was accidentally bolted shut along with the technique it is the
		# price of. It is genuinely open again as of the JUMP hand-off below.
		#
		# Both terms below carry the Noob-to-Pro skill gradient (04 §4.4), but
		# TIME ON WALL is what drives it -- not how squarely the player faces
		# the wall. The facing reading this comment used to describe was ruled
		# out by measurement (correlation -0.19 against time's -0.42); see
		# wall_jump_quality() above for the numbers.
		var jump_cfg: WallrunJumpConfig = config.wallrun_jump
		player.velocity.y = wall_jump_rise_velocity(_time_on_wall, jump_cfg, config.pawn)
		player.velocity += wall_jump_push_direction(player, _normal, jump_cfg) 			* wall_jump_push_away(_time_on_wall, jump_cfg)
		player.move_and_slide()
		# Declared even on this away-transitioning tick, mirroring
		# WalkingMove's and SlideMove's own jump branches: move_and_slide()
		# just ran, so is_on_floor() is a real answer, not a stale one, and
		# reporting it truthfully costs nothing since JumpMove's own first
		# tick will re-declare regardless.
		player.set_grounded(player.is_on_floor())
		# JUMP, not FALLING. A wall kick IS a launch -- the player pressed
		# jump and left the wall rising -- and in the original every one of
		# the seven states holding bCheckForWallClimb is a launch state
		# (11 §11.2). Handing off to Falling instead would drop the player
		# into the one airborne state whose config deliberately does NOT
		# carry check_for_wall_climb, so no further wall could be attached
		# until the next ground contact: no chained wall kicks at all, which
		# is the technique this whole move exists to serve.
		# Jump hands on to Falling by itself once the rise decays past
		# enter_to_falling_z_speed (JumpMove's own check), so nothing here
		# has to guess when the launch stops being one.
		return JUMP

	# Push along the wall's tangent UP TOWARD the energy-curve ceiling
	# (Player.speed_cap()) -- NOT a wall-specific max speed (wall_max_speed is
	# deleted; "the speed ceiling is handed to the energy curve" per spec
	# §5.5). A player who enters already at their own foot-speed ceiling gets
	# little or nothing from this branch, matching wall_running_min_speed's
	# own invariant that a wall run CARRIES speed rather than creating it.
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
	# ⚠️ Read as a vertical SINK speed -- see WallRunConfig's own note on
	# wall_running_velocity_stop_limit.
	if player.velocity.y < config.wall_run.wall_running_velocity_stop_limit:
		return FALLING
	return KEEP
