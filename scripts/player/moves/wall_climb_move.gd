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
## The height this climb ends at, fixed on entry. A climb travels a SET
## DISTANCE; what a run-up buys is arriving sooner, not arriving higher.
var _ceiling: float = 0.0

func _query() -> Dictionary:
	if player.probes == null:
		return Probes.NO_WALL_AHEAD.duplicate()
	return player.probes.wall_ahead_query(player.approach_direction())

## How fast this climb goes up, given the run-up it started with.
##
## THE BASE IS DERIVED, NOT CHOSEN: it is exactly the speed at which a body
## decelerating under the climb's own half gravity arrives at climb_height with
## nothing left. A standing kick therefore always just makes it, whatever
## climb_height and gravity_scale are later retuned to, and only the BONUS is a
## knob anyone has to think about.
##
## Static and taking its inputs plainly, so the debug markers and the HUD can
## show what a run-up is currently worth before the player commits to it.
static func rise_speed(run_speed: float, cfg: WallClimbConfig, pawn: PawnConfig) -> float:
	var climb_gravity: float = maxf(pawn.gravity * cfg.gravity_scale, 0.001)
	var base: float = sqrt(2.0 * climb_gravity * maxf(climb_height_for(run_speed, cfg), 0.0))
	var earned: float = clampf(run_speed / maxf(cfg.run_speed_limit, 0.001), 0.0, 1.0)
	return base + cfg.rise_speed_bonus * earned

## How high THIS climb goes, given the run-up it started with.
##
## ✅ Both ends measured in the original (see WallClimbConfig.climb_height and
## climb_height_running); ⚠️ the line between them is assumed. Static and taking
## its inputs plainly, for the same reason rise_speed() is: the debug markers
## and the HUD show what a run-up is worth before the player commits to it, and
## they must show the number the move will actually use.
static func climb_height_for(run_speed: float, cfg: WallClimbConfig) -> float:
	var earned: float = clampf(run_speed / maxf(cfg.run_speed_limit, 0.001), 0.0, 1.0)
	return lerpf(cfg.climb_height, cfg.climb_height_running, earned)

func enter(_previous: StringName) -> void:
	_aborted = false
	player.set_grounded(false)
	_anchor = Vector2(player.global_position.x, player.global_position.z)
	var wall: Dictionary = _query()
	if not wall["valid"]:
		_aborted = true
		return
	_normal = wall["normal"]

	# Priced BEFORE the run-up is spent: the friction below is about to take it
	# away, and pricing afterwards would read every climb as a standing one.
	#
	# maxf, not assignment: a player already rising faster than the kick is
	# worth keeps what they had. Taking the larger of the two is what stops a
	# well-timed early kick from being PUNISHED by touching the wall.
	var run_up: float = player.horizontal_speed()
	player.velocity.y = maxf(player.velocity.y,
		rise_speed(run_up, cfg, config.pawn))
	# Priced off the SAME run-up rise_speed() was priced off, two lines up --
	# read before the friction below spends it, or a climb would be given the
	# ascent rate of a running kick and the ceiling of a standing one.
	_ceiling = player.global_position.y + climb_height_for(run_up, cfg)

	# The run-up's forward momentum is spent on the wall, not carried through
	# it. Without this the body keeps pressing into the surface and the slide
	# resolution converts the leftover into a shove along the wall.
	var into: float = player.velocity.dot(_normal)
	if into < 0.0:
		player.velocity -= _normal * into

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return FALLING

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
	# ...or the moment it has gone as far as a climb goes, WITH NOTHING LEFT
	# OVER.
	#
	# The residual used to be handed on, so a fast kick carried a little past
	# the top. That is what "speed buys height" looks like, and the measurement
	# rules it out: a standing climb rises 1.30 m and so does a running one, off
	# a higher contact point. Arithmetic agrees -- preserved through the ceiling,
	# the jump's own 6.3 m/s would still be doing 4.35 m/s there and coast
	# another 0.59 m, which is half again as much climb as the measurement
	# allows.
	#
	# So the climb ends at its apex, which is what "the height does not depend
	# on speed" has to mean if speed is also to raise the rate of ascent. Speed
	# still gets you there sooner; it does not get you further.
	if player.global_position.y >= _ceiling:
		player.velocity.y = 0.0
		return FALLING
	var drift: float = Vector2(player.global_position.x, player.global_position.z).distance_to(_anchor)
	if drift > cfg.max_drift:
		return FALLING
	return KEEP
