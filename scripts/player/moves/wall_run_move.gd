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
	# vertical speed that reaches that height under plain gravity, matching
	# how this project reads every other `*ZHeight` field (spec §2.5). Never
	# LOWERS an already-faster upward speed (e.g. a jump that grabbed a wall
	# mid-rise) -- only ever raises it to the floor this represents.
	var lift: float = config.wall_run.wall_running_horisontal_initial_z_height
	if lift > 0.0:
		player.velocity.y = maxf(player.velocity.y, sqrt(2.0 * config.pawn.gravity * lift))

func exit() -> void:
	player.wall_side = 0
	# Nothing else to do here now: the same-wall reattach cooldown
	# (note_wall_detach()/can_attach_wall(), keyed to the wall's own normal)
	# is gone, a deliberate 1:1 deletion -- see falling_move.gd's own note on
	# what replaced it (MoveManager's generic redo_move_time, which arms
	# itself the moment this move exits, with no help needed here).

func physics_update(delta: float, _input: MoveInput) -> StringName:
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
		player.velocity.y = config.wallrun_jump.wall_jump_up
		player.velocity += _normal * config.wallrun_jump.wall_jump_push
		player.move_and_slide()
		# Declared even on this away-transitioning tick, mirroring
		# WalkingMove's and SlideMove's own jump branches: move_and_slide()
		# just ran, so is_on_floor() is a real answer, not a stale one, and
		# reporting it truthfully costs nothing since FallingMove's own first
		# tick will re-declare regardless.
		player.set_grounded(player.is_on_floor())
		return FALLING

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
	player.velocity.y -= config.pawn.gravity * config.wall_run.wall_gravity_scale * delta
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
