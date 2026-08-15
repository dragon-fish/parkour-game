class_name Player
extends CharacterBody3D

# Owns the shared movement data and the movement primitives. It deliberately
# contains no transition logic — that belongs to the states.
#
# State names live on PlayerState, not here: Player references the state
# classes, so the states must not reference Player back.

var config: MovementConfig
var input_source: InputSource
var state_machine: StateMachine

## Downward speed at the moment of the most recent landing. Read by CameraRig.
var last_landing_speed: float = 0.0
## Last polled input, exposed for the debug HUD.
var last_input: MoveInput = MoveInput.new()

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

func setup(cfg: MovementConfig, src: InputSource) -> void:
	config = cfg
	input_source = src
	_build_state_machine()

func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	add_child(state_machine)

	var ground := GroundState.new()
	var air := AirState.new()
	for s in [ground, air]:
		s.player = self
		s.config = config
		state_machine.add_child(s)

	state_machine.register(PlayerState.GROUND, ground)
	state_machine.register(PlayerState.AIR, air)
	state_machine.start(PlayerState.GROUND)

func _physics_process(delta: float) -> void:
	if state_machine == null:
		return
	var input := input_source.poll()
	last_input = input
	_tick_timers(delta, input)
	state_machine.physics_update(delta, input)

func _tick_timers(delta: float, input: MoveInput) -> void:
	if is_on_floor():
		_coyote_timer = config.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if input.jump_pressed:
		_jump_buffer_timer = config.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

## Spends a buffered jump if one is pending and the player is still within
## coyote time. Returns true at most once per press.
func consume_jump() -> bool:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return true
	return false

## World-space horizontal direction the player is asking to move in.
func wish_direction(input: MoveInput) -> Vector3:
	var dir := global_transform.basis * Vector3(input.move.x, 0.0, -input.move.y)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

## Ground movement: converge on the target velocity, and brake when idle.
func ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		horizontal = horizontal.move_toward(Vector3.ZERO, config.ground_friction * delta)
	else:
		horizontal = horizontal.move_toward(wish_dir * target_speed, config.ground_accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

## Air movement: only ever adds speed along wish_dir, and only up to
## air_max_speed measured along that direction. It never brakes, so momentum
## carried in from another state survives — P1's slide depends on this.
func air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed_along_wish := horizontal.dot(wish_dir)
	var headroom := config.air_max_speed - speed_along_wish
	if headroom <= 0.0:
		return
	horizontal += wish_dir * minf(config.air_accel * delta, headroom)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
