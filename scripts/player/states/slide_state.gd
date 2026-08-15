class_name SlideState
extends PlayerState

# A slide is a commitment: it buys speed up front, steers poorly, and ends on
# its own terms. Everything about it is tuned to make the player choose WHERE
# to slide rather than sliding constantly.

var _elapsed: float = 0.0
var _direction: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_direction = horizontal.normalized() if horizontal.length_squared() > 0.0001 else Vector3.ZERO

	# The boost is applied once, on entry — never per tick.
	var boosted := horizontal.length() + config.slide_boost
	player.velocity.x = _direction.x * boosted
	player.velocity.z = _direction.z * boosted

	player.set_capsule_height(config.slide_capsule_height)

func exit() -> void:
	player.set_capsule_height(player.standing_height())

func physics_update(delta: float, input: MoveInput) -> StringName:
	_elapsed += delta

	# Steering is deliberately slow: a slide commits you to a line.
	var wish_dir: Vector3 = player.wish_direction(input)
	if wish_dir != Vector3.ZERO and _direction != Vector3.ZERO:
		var max_turn := config.slide_steer_rate * delta
		var angle := _direction.signed_angle_to(wish_dir, Vector3.UP)
		_direction = _direction.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))

	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed = maxf(speed - config.slide_friction * delta, 0.0)
	player.velocity.x = _direction.x * speed
	player.velocity.z = _direction.z * speed

	if player.consume_jump():
		player.velocity.y = config.jump_velocity
		player.move_and_slide()
		return AIR

	player.velocity.y = -config.floor_snap_speed
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

	if not input.crouch_held:
		return GROUND
	if post_move_speed <= config.slide_exit_speed:
		return GROUND
	if _elapsed >= config.slide_max_duration:
		return GROUND
	return KEEP
