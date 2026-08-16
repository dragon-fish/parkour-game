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
var _crouch_buffer_timer: float = 0.0
## True when a state has asked for the standing capsule back but a ceiling was
## in the way. See request_standing_capsule().
var _standing_restore_pending: bool = false

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
## setup() on the same tick a player enters the tree, and add_child() does
## not run @onready/_ready() synchronously, so it has not fired yet. Verified
## against both a hand-built player and one instantiated from player.tscn
## (tests/world_fixture.gd uses the latter): @onready vars are still null
## immediately after add_child() returns in either case. An @onready-cached
## reference would be null at that point.
func set_capsule_height(height: float) -> void:
	# Any explicit resize supersedes a restore that was still owed — most
	# importantly a fresh slide entered while one was pending, which must not
	# later have the player stood up mid-slide by the deferred restore.
	_standing_restore_pending = false
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return
	if _standing_height <= 0.0:
		_standing_height = capsule.height
	capsule.height = height
	shape_node.position.y = -(_standing_height - height) * 0.5

## Asks for the standing capsule back, honouring the roof. Restores it at once
## when there is room, otherwise records that a restore is OWED and performs it
## on the first tick headroom permits.
##
## This exists because gating the restore on the caller's side cannot work: a
## slide that runs off a ledge must transition to Air whether or not there is a
## ceiling — a player who walks off an edge falls, roof or no roof — so that
## exit path cannot be headroom-gated the way the jump path is. Deferring at
## the CAPSULE instead covers every exit uniformly: jump, crouch release,
## speed decay, timeout, and walking off an edge mid-crawl alike can never
## spawn a 1.8 m capsule inside geometry.
func request_standing_capsule() -> void:
	if has_headroom():
		set_capsule_height(_standing_height)
	else:
		# Set AFTER the branch above, never before: set_capsule_height() clears
		# this flag, so ordering the two the other way round would drop it.
		_standing_restore_pending = true

func _service_pending_capsule_restore() -> void:
	if _standing_restore_pending and has_headroom():
		set_capsule_height(_standing_height)

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
	_crouch_buffer_timer = 0.0
	last_landing_speed = 0.0
	# A reset teleports the player to a known-clear spawn, so a restore owed
	# from a slide under some ceiling is both stale and satisfiable right now.
	# request_standing_capsule() clears the flag on the way through, and
	# re-arms it in the impossible case that the spawn is itself blocked.
	_standing_restore_pending = false
	request_standing_capsule()

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
	# Before the states run, so the body moves this tick at whatever size it is
	# now entitled to. A restore owed from an exit under a ceiling comes back
	# on the first tick there is room for it.
	_service_pending_capsule_restore()

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

	# Deliberately keyed on crouch_PRESSED, not crouch_held: this buffer stores
	# presses, so holding the key down refills it exactly once. A held-state
	# version would re-arm every tick and let a slide re-enter the instant the
	# previous one ended, which is the strobing this gate exists to prevent.
	if input.crouch_pressed:
		_crouch_buffer_timer = config.crouch_buffer_time
	else:
		_crouch_buffer_timer = maxf(_crouch_buffer_timer - delta, 0.0)

## Spends a buffered jump if one is pending and the player is still within
## coyote time. Returns true at most once per press.
func consume_jump() -> bool:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return true
	return false

## Spends a buffered crouch press if one is pending. Returns true at most once
## per press — this is what keeps the roll-into-slide chain reachable without
## reopening the held-key strobe.
func consume_crouch() -> bool:
	if _crouch_buffer_timer > 0.0:
		_crouch_buffer_timer = 0.0
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
