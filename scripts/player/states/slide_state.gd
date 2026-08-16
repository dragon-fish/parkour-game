class_name SlideState
extends PlayerState

# A slide is a commitment: it buys speed up front, steers poorly, and ends on
# its own terms. Everything about it is tuned to make the player choose WHERE
# to slide rather than sliding constantly.

var _elapsed: float = 0.0
var _direction: Vector3 = Vector3.ZERO
## Latched once a slide has spent itself under something too low to stand up
## in. Cleared the moment headroom returns. See _crawl().
var _crawling: bool = false

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_crawling = false
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else Vector3.ZERO

	# The boost is applied once, on entry — never per tick.
	var boosted := horizontal.length() + config.slide_boost
	player.velocity.x = _direction.x * boosted
	player.velocity.z = _direction.z * boosted

	player.set_capsule_height(config.slide_capsule_height)

## Deliberately a REQUEST, not an unconditional restore. The off-edge exit
## below returns AIR whether or not there is headroom — a player who walks off
## a ledge must fall, ceiling or not, so that path cannot be headroom-gated the
## way the jump path is — and _crawl() shuffling off a ledge reaches it too.
## Restoring the 1.8 m capsule here regardless would spawn it inside the roof.
## Player owes the restore and performs it the moment there is room.
func exit() -> void:
	player.request_standing_capsule()

## True while a spent slide is shuffling out from under a ceiling rather than
## sliding. Both are state Slide, so nothing else can tell them apart — the
## arena's traversability test reads this to prove the tunnel is cleared on
## momentum rather than rescued by the safety net.
func is_crawling() -> bool:
	return _crawling

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta

	# Asked once per tick and reused by the crawl latch and the jump gate, so
	# the two cannot disagree within a single frame.
	# `player` is deliberately untyped (see PlayerState), so its return values
	# arrive as Variant and need an explicit type here.
	var blocked: bool = not player.has_headroom()
	var speed := Vector2(player.velocity.x, player.velocity.z).length()

	if not blocked:
		_crawling = false
	elif speed <= config.slide_exit_speed:
		_crawling = true

	if _crawling:
		_crawl(input)
	else:
		_slide(delta, input, speed)

	# A jump out of a slide is refused under a roof on its own merits, quite
	# apart from the capsule: you cannot jump into a ceiling. (The capsule is
	# separately safe either way — see exit().) has_headroom() is checked BEFORE
	# consume_jump() so the short-circuit leaves the buffered press unspent:
	# press jump inside the tunnel and it fires the moment you clear the roof,
	# rather than being silently eaten.
	if not blocked and player.consume_jump():
		player.velocity.y = config.jump_velocity
		player.move_and_slide()
		return AIR

	player.move_and_slide()

	if not player.is_on_floor():
		player.velocity.y = 0.0
		return AIR

	# Read speed back AFTER move_and_slide(): a collision (e.g. sliding into a
	# wall) can shave it down well below the friction-only decay computed
	# above. Using the pre-move value here would let a wall impact leave the
	# slide "stuck" in place until slide_max_duration expires instead of
	# ending promptly.
	var post_move_speed := Vector2(player.velocity.x, player.velocity.z).length()

	# Every exit to standing passes the same gate: crouch-release, speed decay
	# and timeout alike. Stand up into a ceiling once and the body clips
	# through it, so a blocked slide simply continues — crawling, by then.
	# has_headroom() is re-asked here rather than reusing `blocked`, because
	# the move_and_slide() above may have carried the body clear of the roof
	# on this very tick.
	var wants_to_stand := (not input.crouch_held) \
		or post_move_speed <= config.slide_exit_speed \
		or _elapsed >= config.slide_max_duration
	if wants_to_stand and player.has_headroom():
		return GROUND
	return KEEP

## The slide proper: committed steering, friction, and slope.
func _slide(delta: float, input: MoveInput, speed: float) -> void:
	# Steering is deliberately slow: a slide commits you to a line.
	var wish_dir: Vector3 = player.wish_direction(input)
	if wish_dir != Vector3.ZERO and _direction != Vector3.ZERO:
		var max_turn := config.slide_steer_rate * delta
		var angle := _direction.signed_angle_to(wish_dir, Vector3.UP)
		_direction = _direction.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))

	# Slope awareness (spec section 6: a downhill slide must resist decay, or
	# net-accelerate). `grade` is +1 pointing straight down the fall line, -1
	# straight up it, 0 on the flat, so on level ground this reduces exactly to
	# the plain friction decay it replaced.
	var slope_dir := _slope_direction()
	var grade := -slope_dir.y
	# slide_max_speed is a safety RAIL, not a tuning knob: the duration cap is
	# headroom-gated, so a long COVERED downslope has nothing else bounding it
	# and would accelerate without limit — the panel can drive
	# slide_slope_accel to three times its default. The default sits far above
	# anything the arena produces, so it never binds in normal play. The entry
	# boost is not separately clamped because this runs on the very next tick.
	speed = clampf(speed + (config.slide_slope_accel * grade - config.slide_friction) * delta, \
		0.0, config.slide_max_speed)

	# Drive along the SLOPE, scaled so the horizontal magnitude is still
	# `speed`. Steering the body horizontally instead would leave a descent to
	# floor_snap_speed alone, which is not enough to hold the body on a steep
	# ramp at slide speeds — it would part company with the floor and drop the
	# slide into Air partway down.
	var horizontal_len := Vector2(slope_dir.x, slope_dir.z).length()
	if horizontal_len > 0.001:
		var velocity := slope_dir * (speed / horizontal_len)
		player.velocity.x = velocity.x
		player.velocity.z = velocity.z
		player.velocity.y = velocity.y - config.floor_snap_speed
	else:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.velocity.y = -config.floor_snap_speed

## The slide is spent but there is a roof directly overhead, so standing up is
## impossible and the exit to Ground is gated shut. Rather than sit at zero
## speed forever with no transition available and no way in this state to
## generate any, let the player shuffle out under their own input. Steering is
## immediate here, not the slide's committed line: this is no longer a slide,
## it is someone getting out from under something.
func _crawl(input: MoveInput) -> void:
	var wish_dir: Vector3 = player.wish_direction(input)
	if wish_dir == Vector3.ZERO:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	else:
		_direction = wish_dir
		player.velocity.x = wish_dir.x * config.slide_crawl_speed
		player.velocity.z = wish_dir.z * config.slide_crawl_speed
	player.velocity.y = -config.floor_snap_speed

## The slide line projected onto the floor plane, as a unit vector. Falls back
## to the horizontal line whenever there is no usable floor normal to project
## against, which makes every caller behave exactly as it did before slopes
## existed.
func _slope_direction() -> Vector3:
	if _direction == Vector3.ZERO or not player.is_on_floor():
		return _direction
	var normal: Vector3 = player.get_floor_normal()
	if normal.length_squared() < 0.0001:
		return _direction
	var projected := _direction - normal * _direction.dot(normal)
	if projected.length_squared() < 0.0001:
		return _direction
	return projected.normalized()
