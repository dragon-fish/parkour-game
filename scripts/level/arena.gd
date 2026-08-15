class_name Arena
extends Node3D

# Owns the shared MovementConfig instance and the respawn behaviour. The
# config lives here rather than on the player so the tuning panel and the
# player read from the same object.

@export var player: Player
@export var spawn_point: Marker3D
## Leave empty to create a fresh MovementConfig with default values at runtime.
@export var config: MovementConfig

func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
	player.setup(config, KeyboardInputSource.new())
	if player.camera_rig != null:
		player.camera_rig.setup(config)

	# Session-level concern, deliberately not in Player: headless tests
	# instantiate Player directly and must not touch the display server.
	#
	# The headless guard matters: tests/test_arena.gd instantiates this whole
	# scene under --headless, where there is no real display server to capture
	# a pointer with.
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var panel := get_node_or_null("TuningPanel")
	if panel != null:
		panel.config = config

	reset_player()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			reset_player()

func reset_player() -> void:
	player.velocity = Vector3.ZERO
	player.global_position = spawn_point.global_position
	player.rotation = Vector3.ZERO
	# Restart the state machine in Ground so a reset behaves like a fresh
	# spawn (matching _ready()) rather than leaving the machine wherever it
	# was — e.g. still Air if the reset happened mid-fall.
	player.state_machine.start(PlayerState.GROUND)

	# Skip exactly one physics tick before the state machine runs again. The
	# spawn point sits slightly above the floor on purpose (it produces a
	# small landing dip on first settle), so whichever state is active would
	# immediately perturb the teleport on the very next tick: Air applies
	# gravity, Ground applies its floor-snap glue bias — both are sized for
	# normal per-frame movement, not for a mid-air-to-exact-spawn teleport,
	# so either one reintroduces a small but real velocity/position drift in
	# that single frame. This is the same class of single-frame jolt
	# ground_state.gd already guards against on ledge exits; skip one tick so
	# the teleport actually sticks before physics resumes.
	player.set_physics_process(false)
	await get_tree().physics_frame
	player.set_physics_process(true)
