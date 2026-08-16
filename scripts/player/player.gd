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
## True when the most recent landing was a roll. Read by the camera and HUD.
var last_landing_rolled: bool = false
## Last polled input, exposed for the debug HUD.
var last_input: MoveInput = MoveInput.new()

## Assigned in player.tscn. Optional so headless tests can run without one.
@export var camera_rig: CameraRig

var _standing_height: float = 0.0

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

@onready var _stand_clearance: ShapeCast3D = get_node_or_null("StandClearance")

func standing_height() -> float:
	return _standing_height

## True when the standing-size capsule fits where the body currently is.
## Tests that build a Player by hand have no probe node, so absence means yes.
func has_headroom() -> bool:
	if _stand_clearance == null:
		return true
	_stand_clearance.force_shapecast_update()
	return not _stand_clearance.is_colliding()

## Resizes the capsule while keeping its BOTTOM fixed relative to the body
## origin, so footing and is_on_floor() are unaffected by the change.
## Looks the node up live via $CollisionShape3D rather than caching it in an
## @onready var: setup() (below) calls the same lookup before this player's
## own _ready()/onready pass has necessarily run — TestWorld.build() calls
## setup() on the same tick a fixture-built player enters the tree, one
## physics frame before _ready() fires. An @onready-cached reference would be
## null at that point.
func set_capsule_height(height: float) -> void:
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return
	if _standing_height <= 0.0:
		_standing_height = capsule.height
	capsule.height = height
	shape_node.position.y = -(_standing_height - height) * 0.5

func setup(cfg: MovementConfig, src: InputSource) -> void:
	config = cfg
	input_source = src

	# The capsule resource is shared by every instance of player.tscn, so
	# resizing it in place would let one player's slide shrink every other
	# player in the scene — including, in tests, worlds from previous cases.
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule != null:
		var owned := capsule.duplicate() as CapsuleShape3D
		shape_node.shape = owned
		_standing_height = owned.height

	_build_state_machine()

## Clears per-life transient state that outlives a single frame: the coyote
## and jump-buffer timers, and the last landing speed CameraRig reads for its
## dip. Called on a manual reset (Arena's R key) so a leftover buffered jump
## from just before the reset cannot fire the instant the player respawns
## grounded, and so a landing dip from the old life cannot appear after a
## fresh spawn. Does not touch the state machine itself — callers restart
## that separately.
func reset_state() -> void:
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	last_landing_speed = 0.0

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

	var slide := SlideState.new()
	slide.player = self
	slide.config = config
	state_machine.add_child(slide)
	state_machine.register(PlayerState.SLIDE, slide)

	state_machine.start(PlayerState.GROUND)

func _physics_process(delta: float) -> void:
	if state_machine == null:
		return
	var input := input_source.poll()
	last_input = input
	_tick_timers(delta, input)

	var was_airborne := not is_on_floor()
	if camera_rig != null:
		camera_rig.apply_look(input.look, self)

	state_machine.physics_update(delta, input)

	if camera_rig != null:
		if was_airborne and is_on_floor():
			camera_rig.punch_landing(last_landing_speed)
		camera_rig.set_crouch_amount(1.0 if state_machine.current_name == PlayerState.SLIDE else 0.0)
		camera_rig.update_effects(delta, horizontal_speed(), is_on_floor())

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_source is KeyboardInputSource:
		# Only steer the view while the mouse is actually captured. With the
		# cursor released (F1 panel open, or right after Esc) this motion is
		# the human aiming at a slider or a LineEdit, not a look input.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			(input_source as KeyboardInputSource).accumulate_look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_F11:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	var candidate := horizontal + wish_dir * minf(config.air_accel * delta, headroom)
	# INVARIANT: air control must never brake — only redirect/add speed.
	# The Quake-style projection above adds speed along wish_dir, but when
	# wish_dir opposes the existing velocity that addition can still shrink
	# the resultant horizontal SPEED even though it grows along wish_dir
	# (e.g. horizontal (0,0,-5), wish_dir (0,0,1): adding a small amount
	# along +z takes the resultant length from 5.0 down to 4.8). This guard
	# is what actually enforces the invariant: only commit the candidate
	# when it does not shrink horizontal speed, otherwise leave velocity
	# untouched for this tick. Do not remove this check as a "simplification"
	# — without it, holding the opposite key can brake a jump or erase a
	# slide boost carried into the air.
	if candidate.length() < horizontal.length():
		return
	velocity.x = candidate.x
	velocity.z = candidate.z
