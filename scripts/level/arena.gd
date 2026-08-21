class_name Arena
extends Node3D

# Owns the shared MovementConfig instance and the respawn behaviour. The
# config lives here rather than on the player so the tuning panel and the
# player read from the same object.

@export var player: Player
@export var spawn_point: Marker3D
## Leave empty to create a fresh MovementConfig with default values at runtime.
@export var config: MovementConfig

## Re-entrancy guard for reset_player(); see the comment above that function.
var _resetting_physics: bool = false

## Plays before every respawn triggered by a fatal fall -- a beat of "the
## body gives out" (spec, this task) rather than an instant teleport. Not a
## Move: by the time FallUncontrolledMove reaches the ground the body has no
## state left to be in (see the file's own header comment), so this lives on
## the level, alongside reset_player(), instead of in the state machine.
@onready var _death_sequence: DeathSequence = DeathSequence.new()

func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
	player.setup(config, KeyboardInputSource.new())
	if player.camera_rig != null:
		player.camera_rig.setup(config)

	add_child(_death_sequence)
	_death_sequence.finished.connect(reset_player)
	_load_sandbox()
	# Debug visualisation of what the ledge probe sees. Created here rather
	# than baked into the generated scene, so main.tscn stays exactly what its
	# generator produces.
	var markers := GrabMarkers.new()
	markers.name = "GrabMarkers"
	markers.player = player
	add_child(markers)

	# A fall past pawn.falling_uncontrolled_height is unsurvivable in the
	# original (03 §3.1). Respawning is the arena's job, not the player's, and
	# it deliberately reuses the same path as falling out of the level: from the
	# player's side both are 'that life ended'.
	# DEFERRED on purpose. died_from_fall is emitted from inside
	# FallingMove.physics_update(), and _on_died_from_fall() below starts the
	# death sequence, which drives the camera through CameraRig -- neither of
	# which is safe to do while a move is still mid-execution. reset_player()
	# itself (which the sequence's `finished` signal chains into once it ends)
	# also teleports the body and restarts the move manager, and this
	# function's own header already warns it spans a physics frame; a direct
	# connection would have all of that run inside one.
	if not player.died_from_fall.is_connected(_on_died_from_fall):
		player.died_from_fall.connect(_on_died_from_fall, CONNECT_DEFERRED)

	# Session-level concern, deliberately not in Player: headless tests
	# instantiate Player directly and must not touch the display server.
	#
	# The headless guard matters: tests/legacy/test_arena.gd instantiates this
	# whole scene under --headless, where there is no real display server to
	# capture a pointer with -- ARCHIVED by Task 1 and NOT in the running
	# suite, so nothing currently exercises this path; the reasoning still
	# holds for whoever rewrites that test.
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var panel := get_node_or_null("TuningPanel")
	if panel != null:
		panel.config = config

	reset_player()

## Starts the death sequence; reset_player() itself runs once it reports
## `finished` (wired in _ready()), not from here directly.
func _on_died_from_fall() -> void:
	_death_sequence.play(player)

## Loads scenes/sandbox.tscn under the arena, if it exists.
##
## scenes/main.tscn is GENERATED (tools/build_main_scene.gd), so anything added
## to it by hand is destroyed the next time the generator runs -- which happens
## whenever a builder or a config value it reads changes, and is enforced by
## tests/test_generated_scenes.gd. That makes it a bad place to park a ramp you
## want to try out.
##
## sandbox.tscn is not generated and not referenced by any builder, so whatever
## is in it survives. It is optional: absent, this does nothing. It is also
## git-ignored, so experiments do not have to be committed or explained.
const SANDBOX_SCENE := "res://scenes/sandbox.tscn"

func _load_sandbox() -> void:
	if not ResourceLoader.exists(SANDBOX_SCENE):
		return
	var packed: PackedScene = load(SANDBOX_SCENE)
	if packed == null:
		return
	var sandbox: Node = packed.instantiate()
	sandbox.name = "Sandbox"
	add_child(sandbox)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			reset_player()
		elif event.physical_keycode == KEY_K:
			# DEBUG. Routed through died_from_fall rather than reset_player()
			# so it exercises the real chain -- cutscene, then respawn --
			# which is the thing worth being able to trigger on demand.
			if player != null:
				player.died_from_fall.emit()

## Recovers a player who fell out of the level entirely -- off the far edge of
## the (generously sized, see tools/arena_builder.gd's own Floor comment)
## arena floor, or through a genuine hole in the geometry. The practice gaps
## themselves land safely ON the floor now (a missed jump there is a
## teachable "you came up short", not an endless fall -- see this task's own
## report on why that used to be the opposite), so this exists for the
## edge-of-the-world case, not as their landing net. Checked every tick rather
## than relying on the player to press R, since falling forever is not a
## state a human should have to notice and self-rescue from.
func _physics_process(_delta: float) -> void:
	if is_instance_valid(player) and player.global_position.y < -config.pawn.fall_recovery_depth:
		reset_player()

## Teleports the player to spawn and clears its velocity.
##
## NOT synchronous: this spans a physics frame (see below), so it completes
## one tick after the call returns. Callers must not assume the player is
## already at spawn immediately after calling this — await a physics_frame
## first if the result needs to be observed.
func reset_player() -> void:
	# FIRST, before anything else here. Every route into this function is a
	# respawn happening NOW -- the R key, falling out of the level, and the
	# death sequence's own `finished` -- and a sequence still running would go
	# on to fire `finished` at total_duration() and respawn the player a second
	# time, seconds later, on a body that has long since got on with its life.
	# stop() is a no-op on a sequence that is not playing, which is what makes
	# the finished -> reset_player -> stop() route safe rather than recursive.
	# Null-guarded because reset_player() is also reachable before _ready()
	# has added the sequence (a test driving this node by hand).
	if _death_sequence != null:
		_death_sequence.stop()
	player.velocity = Vector3.ZERO
	player.global_position = spawn_point.global_position
	player.rotation = Vector3.ZERO
	player.reset_state()
	if player.camera_rig != null:
		player.camera_rig.reset_state()
	# Restart the move manager in Walking so a reset behaves like a fresh
	# spawn (matching _ready()) rather than leaving the manager wherever it
	# was — e.g. still Falling if the reset happened mid-fall.
	player.move_manager.start(Move.WALKING)

	# Skip exactly one physics tick before the move manager runs again. The
	# spawn point sits slightly above the floor to leave clearance so the
	# capsule never spawns interpenetrating the floor collider — NOT to
	# produce a landing dip (a 0.1 m drop reaches only ~1.4 m/s, versus
	# land_dip_speed_ref = 18 for a full-strength dip, so the dip from this
	# gap alone is a few millimetres and not visually meaningful). Because of
	# that gap, whichever move is active would immediately perturb the
	# teleport on the very next tick if we let it run: Falling applies gravity,
	# Walking applies its floor-snap glue bias — both are sized for normal
	# per-frame movement, not for a mid-air-to-exact-spawn teleport, so
	# either one reintroduces a small but real velocity/position drift in
	# that single frame. This is the same class of single-frame jolt
	# walking_move.gd already guards against on ledge exits; skip one tick so
	# the teleport actually sticks before physics resumes.
	#
	# This ordering is also what test_reset_returns_the_player_to_spawn
	# relies on to pass: it reads player state right after a single
	# `await step(1)` (one tree.physics_frame), so that signal must fire
	# strictly after the physics step it gates and before player's own
	# _physics_process resumes — that is Godot's documented behaviour here,
	# but it is exactly the assumption this whole mechanism is built on, so
	# it is worth stating plainly rather than leaving it implicit.
	#
	# Re-entrancy: mashing the reset key calls this again before the await
	# below resolves. _resetting_physics makes that idempotent — a reset
	# that lands mid-cycle still re-teleports immediately (the assignments
	# above already ran), but does not start a second, overlapping
	# disable/await/enable pair; the one cycle already in flight is left to
	# finish and re-enable physics processing once.
	if _resetting_physics:
		return
	_resetting_physics = true
	player.set_physics_process(false)
	await get_tree().physics_frame
	_resetting_physics = false
	# player (or the whole arena) may have been freed while this coroutine
	# was suspended — e.g. queue_free() called shortly after a reset — so
	# guard the resumed access rather than touching a freed instance.
	if is_instance_valid(player):
		player.set_physics_process(true)
