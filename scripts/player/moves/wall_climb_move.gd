class_name WallClimbMove
extends AirborneMove

# Running straight at a wall and kicking vertically up it.
#
# Extends AirborneMove rather than Move, unlike its sibling WallRunMove, and
# that is not stylistic: TdMove_WallClimb sets bCheckForGrab AND
# bCheckForVaultOver, so a climb has to keep probing for a lip to catch or an
# obstacle to clear. probe_transition() already is that probing, and inheriting
# it is how "kick up, catch the lip" stays one continuous motion instead of two
# moves the player has to aim separately.

## The wall's outward normal, refreshed every tick from the probe -- a climb
## that loses its wall ends, so this is never stale.
var _normal: Vector3 = Vector3.ZERO
var _aborted: bool = false
## Where the climb started, horizontally. Only max_drift consumes it.
var _anchor: Vector2 = Vector2.ZERO

func _query() -> Dictionary:
	if player.probes == null:
		return Probes.NO_WALL_AHEAD.duplicate()
	var heading: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	return player.probes.wall_ahead_query(heading)

## The height this climb is worth, from the speeds it started with.
##
## Static and taking its inputs plainly, so the entry test can price a climb
## without one having to happen -- and so the debug markers can show the player
## what their current run-up would buy before they commit to it.
static func climb_height(run_speed: float, rise_speed: float, cfg: WallClimbConfig) -> float:
	var from_run: float = cfg.run_speed_height \
		* clampf(run_speed / maxf(cfg.run_speed_limit, 0.001), 0.0, 1.0)
	# Only RISING counts. Falling onto a wall buys nothing, which is what makes
	# kicking early in a jump worth so much more than kicking at the apex.
	var from_rise: float = cfg.rise_speed_height \
		* clampf(maxf(rise_speed, 0.0) / maxf(cfg.rise_speed_limit, 0.001), 0.0, 1.0)
	return from_run + from_rise

func enter(_previous: StringName) -> void:
	_aborted = false
	player.set_grounded(false)
	_anchor = Vector2(player.global_position.x, player.global_position.z)
	var wall: Dictionary = _query()
	if not wall["valid"]:
		_aborted = true
		return
	_normal = wall["normal"]

	# Priced BEFORE the run-up is spent, using the speeds that were carried
	# into the wall. Doing it after the friction below would price the climb
	# from a body that has already stopped.
	var wanted: float = climb_height(player.horizontal_speed(), player.velocity.y, cfg)
	var climb_gravity: float = config.pawn.gravity * cfg.gravity_scale
	var rise: float = sqrt(2.0 * maxf(climb_gravity, 0.001) * maxf(wanted, 0.0))
	# maxf, not assignment: a player already rising faster than the kick is
	# worth keeps what they had. Taking the larger of the two is what stops a
	# well-timed early kick from being PUNISHED by touching the wall.
	player.velocity.y = maxf(player.velocity.y, rise)

	# The run-up's forward momentum is spent on the wall, not carried through
	# it. Without this the body keeps pressing into the surface and the slide
	# resolution converts the leftover into a shove along the wall.
	var into: float = player.velocity.dot(_normal)
	if into < 0.0:
		player.velocity -= _normal * into

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted:
		return FALLING

	# Q, at any point in the climb. Checked before the wall is re-queried
	# because the turn does not need a wall to still be there -- by the time
	# the player has decided to spin, the climb is over either way.
	if input.turn_pressed and player.move_manager.can_enter(TURN_180):
		player.pending_wall_normal = _normal
		return TURN_180

	var wall: Dictionary = _query()
	if not wall["valid"]:
		return FALLING
	_normal = wall["normal"]

	# A lip to catch or an obstacle to clear beats carrying on up a blank wall.
	# ✅ bCheckForGrab / bCheckForVaultOver, see WallClimbConfig's _init().
	var probed := probe_transition()
	if probed != KEEP:
		return advance_and_hand_off(probed)

	# ✅ WallClimbingVerticalFriction. Applied to the horizontal plane only:
	# the whole move is about converting that horizontal run into height, and
	# the vertical component is gravity's business two lines down.
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	horizontal = horizontal.move_toward(Vector3.ZERO, cfg.horizontal_friction * delta)
	player.velocity.x = horizontal.x
	player.velocity.z = horizontal.z

	player.velocity.y -= config.pawn.gravity * cfg.gravity_scale * delta
	player.velocity -= _normal * cfg.wall_stick_force

	player.move_and_slide()
	player.set_grounded(player.is_on_floor())
	if player.grounded:
		return WALKING
	# The climb is over the moment it stops going up. There is no downward
	# phase: sliding back down a wall is not a thing the original does, and
	# half-gravity on the way down would read as floating.
	if player.velocity.y <= 0.0:
		return FALLING
	var drift: float = Vector2(player.global_position.x, player.global_position.z).distance_to(_anchor)
	if drift > cfg.max_drift:
		return FALLING
	return KEEP
