class_name WallRunState
extends PlayerState

# Wall running is physics-driven, unlike the scripted vault and mantle: the
# player keeps real velocity and real collisions, gravity is merely weakened
# and a push is applied along the wall.

var _elapsed: float = 0.0
var _normal: Vector3 = Vector3.ZERO
var _along: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	# Wall running IS physics-driven, but grounded-ness is still DECLARED, never
	# inferred -- P2 replaced is_on_floor() as the authority precisely so that
	# no state can leave a stale value behind. This first declaration covers
	# THIS tick only (the tick AirState handed off without ever calling
	# move_and_slide()); every subsequent tick's physics_update() below
	# declares again from that tick's own move_and_slide() result. See the
	# CRITICAL note there for why a single declaration here would not be
	# enough.
	player.set_grounded(false)
	var query: Dictionary = player.probes.wall_query()
	_normal = query["normal"]
	player.wall_side = query["side"]

	# Run along the wall in whichever of the two tangent directions the player
	# is already moving. A wall never reverses you.
	var tangent: Vector3 = _normal.cross(Vector3.UP).normalized()
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_along = tangent if tangent.dot(horizontal) >= 0.0 else -tangent

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
	player.note_wall_detach(_normal)

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta

	# A wall jump is a fresh, edge-triggered press, not a buffered/coyote
	# ground jump: player.consume_jump() requires BOTH the jump buffer AND
	# the coyote timer to be alive, and the coyote timer only ever refills
	# while player.grounded is true -- which this state, being airborne by
	# definition, never declares. Using consume_jump() here would mean the
	# wall jump could fire only in the rare case a ground-jump's coyote grace
	# happened to still be running, i.e. essentially never. Read the raw press
	# instead, the same way LedgeHangState reads input.jump_pressed directly
	# for its own climb trigger rather than going through the ground-jump
	# buffer.
	if input.jump_pressed:
		player.velocity.y = config.wall_jump_up
		player.velocity += _normal * config.wall_jump_push
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
	if along_speed < config.wall_max_speed:
		var add := minf(config.wall_accel * delta, config.wall_max_speed - along_speed)
		player.velocity += _along * add

	# Weakened gravity plus a gentle pull into the wall so the body stays glued
	# through small surface irregularities.
	player.velocity.y -= config.gravity * config.wall_gravity_scale * delta
	player.velocity -= _normal * config.wall_stick_force

	player.move_and_slide()

	# CRITICAL: declared EVERY tick this state stays active, not just once in
	# enter(). StateMachine's invariant only checks "declared at least once
	# since entry" -- a state that declared a stale value in enter() and never
	# again would satisfy that check while lying for the rest of its run. Here
	# it is never stale: move_and_slide() just ran this tick, so is_on_floor()
	# is a fresh, true reading every time this line executes, for every branch
	# below (GROUND, AIR, and KEEP alike).
	player.set_grounded(player.is_on_floor())

	if player.grounded:
		return GROUND
	if _elapsed >= config.wall_max_duration:
		return AIR
	if Vector2(player.velocity.x, player.velocity.z).length() < config.wall_exit_speed:
		return AIR
	var query: Dictionary = player.probes.wall_query()
	if not query["valid"]:
		return AIR
	return KEEP
