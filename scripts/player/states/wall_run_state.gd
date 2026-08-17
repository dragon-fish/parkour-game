class_name WallRunState
extends PlayerState

# Wall running is physics-driven, unlike the scripted vault and mantle: the
# player keeps real velocity and real collisions, gravity is merely weakened
# and a push is applied along the wall.

## Shape returned by _query_wall() when there is no probe to ask, matching
## Probes.wall_query()'s own "nothing found" shape.
const _NO_WALL := {"valid": false, "normal": Vector3.ZERO, "side": 0}

var _elapsed: float = 0.0
var _normal: Vector3 = Vector3.ZERO
var _along: Vector3 = Vector3.ZERO
## Set in enter() when the wall query comes back invalid: there is nothing to
## run along, so physics_update() hands straight back to Air without ever
## touching velocity or the reattach cooldown. See enter()'s note.
var _aborted: bool = false

## Guarded the same way VaultState/LedgeHangState guard their own probe
## lookups: `player.probes` is null-checked at every call site rather than
## dereferenced directly, so this state degrades the same way its siblings do
## for a hand-built player with no probe rig, instead of crashing.
func _query_wall() -> Dictionary:
	if player.probes == null:
		# .duplicate(), never the const itself: see probes.gd's own NO_HIT note
		# -- a const Dictionary is read-only, and returning the shared instance
		# directly would hand every caller the same read-only object.
		return _NO_WALL.duplicate()
	return player.probes.wall_query()

## Highest Y a chain of wall-jumps may lift the player above the last real
## ground contact (player.ground_reference_y) -- see the wall-jump branch of
## physics_update() below for the full reasoning. Factored out because it is
## enforced at TWO points, not one: once at the instant a wall-jump fires
## (clamping the impulse itself), and once every tick this state is active
## (clamping the CLIMB, since leftover positive vy from the previous kick can
## otherwise still creep past this same ceiling while running along the next
## wall under weakened wall_gravity_scale, before the next jump ever fires --
## confirmed directly: without this second clamp, a synthetic long chain
## overshot the kick-time-only ceiling by nearly a metre). Both call sites
## must agree on the exact same number, so this is computed once, not copied.
func _height_ceiling() -> float:
	var jump_peak_height: float = (config.pawn.base_jump_z * config.pawn.base_jump_z) \
		/ (2.0 * maxf(config.pawn.gravity, 0.001))
	var wall_jump_peak_rise: float = (config.wallrun_jump.wall_jump_up * config.wallrun_jump.wall_jump_up) \
		/ (2.0 * maxf(config.pawn.gravity, 0.001))
	return player.ground_reference_y + jump_peak_height + wall_jump_peak_rise

## Recomputes _along from the CURRENT _normal and the player's CURRENT
## horizontal velocity. Called every time _normal is (re)assigned -- once in
## enter(), and again every tick in physics_update() -- so the tangent tracks
## the true wall surface instead of the angle it happened to have on attach.
func _derive_along() -> void:
	var tangent: Vector3 = _normal.cross(Vector3.UP).normalized()
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_along = tangent if tangent.dot(horizontal) >= 0.0 else -tangent

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_aborted = false
	# Wall running IS physics-driven, but grounded-ness is still DECLARED, never
	# inferred -- P2 replaced is_on_floor() as the authority precisely so that
	# no state can leave a stale value behind. This first declaration covers
	# THIS tick only (the tick AirState handed off without ever calling
	# move_and_slide()); every subsequent tick's physics_update() below
	# declares again from that tick's own move_and_slide() result. See the
	# CRITICAL note there for why a single declaration here would not be
	# enough.
	player.set_grounded(false)

	# AirState already null-checks player.probes AND requires a valid
	# wall_query() before ever transitioning here, so this branch is not
	# reachable in normal play. Kept as a genuinely safe guard for a future
	# caller that skips that gate, mirroring VaultState's/LedgeHangState's own
	# _aborted pattern: a zero normal would give _derive_along() a zero
	# tangent (no push direction at all) and would poison the reattach
	# cooldown with a zero-vector "wall" on exit (see note_wall_detach()) --
	# there is no safe wall to attach to when the probe found nothing, so
	# attach to none and let the player fall.
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
	# `player` is deliberately untyped (see PlayerState), so `player.velocity`
	# arrives as Variant and `:=` cannot infer a type from it -- annotate
	# explicitly, matching the pattern SlideState already uses for the same
	# reason.
	var into: float = player.velocity.dot(_normal)
	if into < 0.0:
		player.velocity -= _normal * into

func exit() -> void:
	player.wall_side = 0
	# Only a wall this state actually attached to should arm the reattach
	# cooldown -- an aborted entry (see enter()'s note) never assigned a real
	# _normal, and keying the cooldown to Vector3.ZERO would either poison
	# every future attach (ZERO.dot(anything) == 0, which is never >=
	# wall_same_normal_dot, so harmlessly it would just never match -- but
	# relying on that coincidence instead of stating the guard explicitly is
	# exactly the kind of thing review flagged) or waste a cooldown slot on a
	# wall that was never actually run.
	if not _aborted:
		player.note_wall_detach(_normal)

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return AIR
	_elapsed += delta

	# Refresh the wall's geometry EVERY tick from a fresh query, not just
	# once at entry. IMPORTANT (review): _normal used to be captured once in
	# enter() and never refreshed, even though a query was already being made
	# every tick to check validity. On a curved or angled wall that meant (a)
	# the jump push and stick force kept pointing along the STALE entry
	# normal, (b) _along drifted off the true tangent and bled speed into the
	# wall, and (c) exit() keyed the reattach cooldown on the entry normal
	# too, so a wall curved enough could be immediately re-attached the
	# instant it was left -- the exact exploit the cooldown exists to stop.
	# Reusing the query already being paid for here (rather than adding a
	# second one) fixes all three at once: everything below this point reads
	# the CURRENT surface.
	var query: Dictionary = _query_wall()
	if not query["valid"]:
		return AIR
	_normal = query["normal"]
	player.wall_side = query["side"]
	_derive_along()

	# A wall jump is a fresh press, not a ground-style coyote jump: the
	# jump/coyote timer only refills while player.grounded is true, and this
	# state truthfully declares grounded=false every tick, so
	# player.consume_jump() is permanently dead here. But a plain
	# `_input.jump_pressed` edge check is ALSO wrong (verified, see
	# task-1-report.md): AirState hands off to this state's enter() the
	# moment it detects a wall, before this state's own first
	# physics_update() ever runs, so a press made on the attach tick -- or
	# any of the up-to jump_buffer_time ticks before it, exactly like every
	# other buffered jump in this game -- would land on a tick this state
	# never sees jump_pressed==true on, and get silently dropped on the most
	# timing-sensitive move there is. consume_buffered_jump() reads the same
	# buffer GroundState/AirState do, just without the coyote requirement
	# that would otherwise be impossible to satisfy here, and spends it so a
	# consumed press cannot also fire a second jump later.
	if player.consume_buffered_jump():
		# BOUNDING A CHAINED CLIMB (see this task's own report): this used
		# to unconditionally ASSIGN velocity.y = config.wall_jump_up on
		# every wall-jump, with no reference to how much height the chain
		# had already banked. Between two CLOSE, oppositely-facing walls
		# (the zig-zag section's own ZigLeft/ZigRight pairs are built to
		# allow exactly this -- their same-wall cooldown deliberately
		# never blocks an opposite normal, see can_attach_wall()'s own
		# comment) the reattach happens almost instantly, leaving gravity
		# no real time to claw any of the previous kick back before this
		# one erased it anyway. The result: every hop granted the SAME
		# fixed rise regardless of hop count, so total height grew
		# linearly with the number of wall-jumps in the chain -- unbounded
		# given enough wall.
		#
		# The research (04-墙面动作.md §4.4, 09-Godot移植指南.md §9.1) has no
		# sourced number for a total-climb ceiling -- ME's own WallrunJump
		# push is a bounded PER-USE skill gradient (Noob 120 -> Pro 520
		# uu/s, i.e. a single-kick range, not something that compounds
		# across hops), and wall running there ends via horizontal
		# velocity decay, not a timer or a height governor. Lacking a
		# sourced total-height rule, this generalises a rule this
		# codebase ALREADY states for the horizontal axis instead of
		# inventing a new one: wall_min_speed's own comment says wall
		# running "is a way to CARRY speed, never a way to create it from
		# nothing" (also pinned by
		# tests/test_movement_config.gd's test_wall_running_cannot_
		# create_speed_beyond_what_foot_speed_reaches). Applied to height:
		# a wall-jump chain may CARRY the player up, but the total it can
		# add above the last real ground contact is capped at what a
		# single ground jump reaches (jump_peak_height) plus one
		# wall-jump's own textbook peak rise (wall_jump_up^2 / (2 *
		# gravity), decelerating under PLAIN gravity -- never weakened,
		# since gravity is only ever scaled by wall_gravity_scale while
		# actually ATTACHED, not during the brief airborne hop between
		# two walls) -- one bonus kick's worth on top of an ordinary jump,
		# not a fresh full kick minted every time a hand touches a wall.
		# Further hops within the same climb redistribute that budget
		# rather than stacking a new one, so the impulse smoothly shrinks
		# toward zero as the ceiling is approached instead of hitting an
		# arbitrary hard wall.
		var height_ceiling: float = _height_ceiling()
		var remaining_height: float = maxf(height_ceiling - player.global_position.y, 0.0)
		var max_vy: float = sqrt(2.0 * maxf(config.pawn.gravity, 0.001) * remaining_height)
		player.velocity.y = minf(config.wallrun_jump.wall_jump_up, max_vy)
		player.velocity += _normal * config.wallrun_jump.wall_jump_push
		player.move_and_slide()
		# Declared even on this away-transitioning tick, mirroring
		# GroundState's and SlideState's own jump branches: move_and_slide()
		# just ran, so is_on_floor() is a real answer, not a stale one, and
		# reporting it truthfully costs nothing since AirState's own first
		# tick will re-declare regardless.
		player.set_grounded(player.is_on_floor())
		return AIR

	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var along_speed := horizontal.dot(_along)
	if along_speed < config.wall_run.wall_max_speed:
		var add := minf(config.wall_run.wall_accel * delta, config.wall_run.wall_max_speed - along_speed)
		player.velocity += _along * add

	# Weakened gravity plus a gentle pull into the wall so the body stays glued
	# through small surface irregularities.
	player.velocity.y -= config.pawn.gravity * config.wall_run.wall_gravity_scale * delta
	player.velocity -= _normal * config.wall_run.wall_stick_force

	# SECOND enforcement point for the same climb bound the wall-jump branch
	# above clamps at kick-time -- see _height_ceiling()'s own comment on why
	# one clamp alone is not enough. A player can reattach to the next wall
	# still carrying leftover positive vy from the last kick (the free-flight
	# arc between two close walls does not always have time to peak before
	# the next one is reached); left alone, THIS state's own weakened gravity
	# then lets that leftover velocity keep lifting the player, tick after
	# tick, well past the kick-time ceiling before the next jump ever fires.
	# Only ever removes upward drift once AT the ceiling -- ordinary gravity
	# above still applies every tick regardless, so this never pulls the
	# player down through a wall they legitimately reached.
	if player.velocity.y > 0.0 and player.global_position.y >= _height_ceiling():
		player.velocity.y = 0.0

	player.move_and_slide()

	# CRITICAL: declared EVERY tick this state stays active, not just once in
	# enter(). StateMachine's invariant only checks "declared at least once
	# since entry" -- a state that declared a stale value in enter() and never
	# again would satisfy that check while lying for the rest of its run. Here
	# it is never stale: move_and_slide() just ran this tick, so is_on_floor()
	# is a fresh, true reading every time this line executes, for every branch
	# below (GROUND and AIR alike, and the fall-through KEEP).
	player.set_grounded(player.is_on_floor())

	if player.grounded:
		return GROUND
	if _elapsed >= config.wall_run.wall_max_duration:
		return AIR
	# wall_exit_speed is measured as TOTAL horizontal speed (matching
	# wall_min_speed's own measurement), not projected onto _along -- see
	# WallRunConfig's own note on this field.
	if Vector2(player.velocity.x, player.velocity.z).length() < config.wall_run.wall_exit_speed:
		return AIR
	return KEEP
