class_name SpectatorCamera
extends Camera3D

# A free camera for looking at something the player is not driving.
#
# ✅ THE OWNER, on the animation lab: "让一个 NPC 去跑，玩家把我的鼠标劫持了，我要当
# 旁观者相机."
#
# 🎯 THE EDITOR IDIOM, not the game one: HOLD THE RIGHT BUTTON to look and fly,
# release it and the pointer is a pointer again. That is what lets WASD mean
# "fly" while the button is down and leaves A and D free to walk the recording
# when it is not -- the lab's own keys and the camera's never both apply.

@export var look_sensitivity := 0.0025
@export var speed := 6.0
@export var fast_multiplier := 3.0
@export var slow_multiplier := 0.25

var _flying := false
var _yaw := 0.0
var _pitch := 0.0
var _last_tick: int = 0

func _ready() -> void:
	# Whatever it was pointed at in the scene is where it starts looking.
	_yaw = rotation.y
	_pitch = rotation.x
	current = true
	_last_tick = Time.get_ticks_usec()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_flying = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _flying \
			else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _flying:
		var motion: Vector2 = (event as InputEventMouseMotion).relative
		_yaw -= motion.x * look_sensitivity
		# Stopped just short of straight up and down, where yaw stops meaning
		# anything and the view rolls over.
		_pitch = clampf(_pitch - motion.y * look_sensitivity,
			-PI * 0.49, PI * 0.49)
		rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# ⚠️ A REAL CLOCK, NOT THE FRAME'S. The lab freezes the world to scrub it
	# (Engine.time_scale goes to zero), and a scaled delta is zero with it -- so
	# a camera driven by _process(delta) stops dead at exactly the moment it is
	# needed. Scaling the frozen delta back up does not help either: zero times
	# anything is still zero.
	var now: int = Time.get_ticks_usec()
	var real: float = float(now - _last_tick) / 1000000.0
	_last_tick = now
	if not _flying:
		return
	real = minf(real, 0.1)
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish -= basis.z
	if Input.is_key_pressed(KEY_S):
		wish += basis.z
	if Input.is_key_pressed(KEY_A):
		wish -= basis.x
	if Input.is_key_pressed(KEY_D):
		wish += basis.x
	if Input.is_key_pressed(KEY_E):
		wish += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		wish -= Vector3.UP
	if wish == Vector3.ZERO:
		return
	var rate := speed
	if Input.is_key_pressed(KEY_SHIFT):
		rate *= fast_multiplier
	elif Input.is_key_pressed(KEY_CTRL):
		rate *= slow_multiplier
	global_position += wish.normalized() * rate * real
