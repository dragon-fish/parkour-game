class_name Arena
extends Node3D

# Owns the shared MovementConfig instance and the respawn behaviour. The
# config lives here rather than on the player so the tuning panel and the
# player read from the same object.

@export var player: Player
@export var spawn_point: Marker3D
## Leave empty to create a fresh MovementConfig with default values at runtime.
@export var config: MovementConfig
## This level's atmosphere. Leave EMPTY and Arena never touches the
## WorldEnvironment's fog settings at all -- whatever the scene's own
## Environment resource says stands, which is what a hand-authored sky wants
## and what keeps a bare test-built Arena from needing one. Assign a FogConfig
## (templates/base_level.tscn does) and this node drives both fogs from it
## every frame instead. See fog_config.gd for why fog is a level's property
## and not one of MovementConfig's groups.
@export var fog: FogConfig

## Holding R this long before release clears the active checkpoint (debug).
const CHECKPOINT_CLEAR_HOLD := 1.0
var _r_pressed_at_ms: int = -1

## Re-entrancy guard for reset_player(); see the comment above that function.
var _resetting_physics: bool = false

## Plays before every respawn triggered by a fatal fall -- a beat of "the
## body gives out" (spec, this task) rather than an instant teleport. Not a
## Move: by the time FallUncontrolledMove reaches the ground the body has no
## state left to be in (see the file's own header comment), so this lives on
## the level, alongside reset_player(), instead of in the state machine.
@onready var _death_sequence: DeathSequence = DeathSequence.new()

## The resting cold-blue tint. ⚠️ FOUR PLACES CARRY THIS COLOUR AND ALL FOUR
## MUST AGREE: here, templates/base_level.tscn, tools/arena_builder.gd, and
## scenes/main.tscn. This one WINS AT RUNTIME -- Arena._process() re-applies
## it every frame (so an F1 drag of ambient_cold_strength takes effect live),
## which means a colour tuned in the editor and saved into a .tscn alone is
## overwritten the moment the level runs. The scene copies are what the
## EDITOR viewport shows; this constant is what the game shows.
##
## 📌 The .tscn files cannot hold that warning themselves: Godot strips the
## `;` comments out of a scene file whenever the editor re-saves it, which
## is how the previous copy of this note disappeared.
const COLD_AMBIENT_TINT := Color(0.223529, 0.466667, 0.741176)
## The "no tint" end of CameraConfig.ambient_cold_strength: plain white, so a
## strength of 0 leaves only the environment's own ambient_light_energy
## setting the shadow brightness, with no colour cast at all.
const NEUTRAL_AMBIENT_TINT := Color(1.0, 1.0, 1.0)

## The smallest gap Arena will leave between FogConfig's two fade distances.
## Not a tunable: it exists only so the end distance can never land ON the
## begin distance or on 0, both of which Godot reads as something other than
## "a very short fade" -- see _apply_fog() for what each would actually do.
const MIN_FOG_FADE_SPAN := 0.01
## The shortest volumetric fog range Arena will ask Godot for. Same job as
## MIN_FOG_FADE_SPAN above: a dial dragged to zero must not hand the renderer a
## degenerate volume.
const MIN_VOLUMETRIC_DISTANCE := 1.0
## How much the depth fog is allowed to obscure the SKY. Zero, deliberately:
## the fog's job here is hiding unfinished GROUND, and a fog that also eats the
## sky turns a rooftop view into a flat white void -- worse than the horizon it
## was hired to hide. Not a dial because no level has wanted the other answer;
## make it one the first time one does.
const FOG_SKY_AFFECT := 0.0

## Found by name, same as TuningPanel below -- both templates/base_level.tscn
## and the generated main.tscn name this node "WorldEnvironment" (see
## tools/arena_builder.gd's build()). Null-checked rather than @export'd: a
## bare Arena built by a test with no WorldEnvironment sibling must not crash.
@onready var _world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment")

func _ready() -> void:
	# ⚠️ DIAGNOSTIC, and it is here because nothing outside can see this.
	# ResourceLoader's progress covers main.tscn's dependency tree -- nine
	# entries -- and finishes in about 80 ms. Everything below runs on the main
	# thread AFTER that, under whatever curtain happens to be up, and no loader
	# API can report it. ✅ THE OWNER: "那就加可观测性，打日志，我来真的点一次看看
	# 控制台输出什么东西." Take these out once the answer is in.
	# CUMULATIVE from the top of _ready, not per-step -- GDScript lambdas
	# capture by VALUE, so a `_t = now` in here would update the closure's own
	# copy and every line would read as a delta from zero. Subtract adjacent
	# rows for the cost of a step.
	var _began := Time.get_ticks_msec()
	var _mark := func(what: String) -> void:
		print("[load]   Arena._ready %-24s %6d ms elapsed" % [what, Time.get_ticks_msec() - _began])

	if config == null:
		config = MovementConfig.new()
	player.setup(config, KeyboardInputSource.new())
	_mark.call("player.setup")
	if player.camera_rig != null:
		player.camera_rig.setup(config)
		# The viewing preference from last session. Here rather than in the
		# rig's own setup() because that runs in tests, where a file written by
		# an earlier run has no business deciding what the test starts in.
		player.camera_rig.load_preferences()
	_mark.call("camera_rig.setup+prefs")

	# AFTER setup(), which is what gives the player its config -- the mount
	# transform an attach captures is measured against the capsule, and the
	# capsule's height comes from there.
	_load_body_profile()
	_mark.call("_load_body_profile")

	add_child(_death_sequence)
	_death_sequence.finished.connect(reset_player)
	_load_calibration_course()
	_mark.call("_load_calibration_course")
	# Debug visualisation of what the ledge probe sees. Created here rather
	# than baked into the generated scene, so main.tscn stays exactly what its
	# generator produces.
	var markers := GrabMarkers.new()
	markers.name = "GrabMarkers"
	markers.player = player
	add_child(markers)

	# The same, for the forward wall probe: whether the wall ahead can be kicked
	# up, and how high the run-up currently being carried would get.
	var wall_markers := WallClimbMarkers.new()
	wall_markers.name = "WallClimbMarkers"
	wall_markers.player = player
	add_child(wall_markers)

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
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var panel := get_node_or_null("TuningPanel")
	if panel != null:
		panel.config = config
		# The level's own dials, handed over the same way and for the same
		# reason: the panel builds its UI one deferred frame later, so an
		# assignment here is in time. Fog rides a SEPARATE field rather than
		# being folded into `config` -- see TuningPanel.collect_fog_tunables()
		# for why a feel preset must not be able to carry a level's weather.
		panel.fog = fog

	reset_player()
	_mark.call("markers + reset_player")

## Starts the death sequence; reset_player() itself runs once it reports
## `finished` (wired in _ready()), not from here directly.
func _on_died_from_fall() -> void:
	_death_sequence.play(player)

## Graded obstacles for judging what the move system does with each, by running
## at them. Committed, because the numbers behind it
## came out of the original with a stopwatch and are worth not losing -- see
## tools/build_calibration_course.gd.
const CALIBRATION_SCENE := "res://scenes/generated/calibration_course.tscn"

## Whether to drop the calibration course into this level.
##
## ✅ OFF BY DEFAULT, at the owner's request: "能不能别让 calibration_course 出现在
## 每一个场景里." This script is the one on templates/base_level.tscn as well as on
## main.tscn, so a course loaded unconditionally turned up in every level built
## from that template -- including whiteboxes where it is 60 m of scenery nobody
## asked for.
##
## The generated arena turns it on, which is where a bench of graded obstacles
## belongs.
## Whether this level grabs the pointer on the way in.
##
## ✅ OFF FOR THE ANIMATION LAB, which is a form with a 3D viewport rather than a
## game: "玩家把我的鼠标劫持了，我要当旁观者相机." A level you play wants the pointer;
## a level you edit in wants a cursor.
@export var capture_mouse: bool = true

@export var load_calibration_course: bool = false

## The body this level plays with, if the file is there.
##
## ⚠️ NOT A SCENE REFERENCE, and it cannot be one. The profile points at a
## licensed model that is not in the repository, so a committed main.tscn naming
## it would break every checkout without that model -- and fail
## test_generated_scenes.gd, which compares the builder's output against what is
## committed. Loading it at runtime keeps the generated scene exactly what its
## generator produces, and a checkout with no model simply plays with no body.
const BODY_PROFILE := "res://scenes/player/local/profiles/vrm_test.tres"

## Which profile the machine's owner is currently playing with -- a git-ignored
## ConfigFile (the whole profiles/ directory is ignored) so switching bodies is
## editing one line, not editing any scene. ✅ THE OWNER: "搞一个被 ignore 的文件
## 来配置当前使用的 body profile." Format:
##
##     [body]
##     profile="res://scenes/player/local/profiles/vrm_test.tres"
##
## Absent, BODY_PROFILE above stays the fallback, which keeps the old behaviour.
const LOCAL_PROFILE_CONFIG := "res://scenes/player/local/profiles/local.cfg"

## Gives the player a body when the scene did not name one.
##
## ✅ THE OWNER: "干脆给 main 也挂上人物模型嘛." Only the old sandbox carried the profile,
## because only a git-ignored scene can afford to reference a git-ignored
## resource -- and with this hook a committed scene never has to: leave the
## Player's Body Profile empty and the local config dresses it on entry.
func _load_body_profile() -> void:
	if player == null or player.body_profile != null:
		return
	var path: String = BODY_PROFILE
	var local := ConfigFile.new()
	if local.load(LOCAL_PROFILE_CONFIG) == OK:
		path = str(local.get_value("body", "profile", BODY_PROFILE))
	if not ResourceLoader.exists(path):
		return
	var profile := load(path) as BodyProfile
	if profile != null:
		player.adopt_body_profile(profile)

func _load_calibration_course() -> void:
	if not load_calibration_course:
		return
	if not ResourceLoader.exists(CALIBRATION_SCENE):
		return
	var packed: PackedScene = load(CALIBRATION_SCENE)
	if packed == null:
		return
	var course: Node = packed.instantiate()
	course.name = "CalibrationCourse"
	# Well clear of the generated arena, which occupies the origin outward.
	if course is Node3D:
		(course as Node3D).position = Vector3(0.0, 0.0, 60.0)
	add_child(course)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.physical_keycode == KEY_R:
		# Hold-to-interact, ✅ the owner's second cut (release-judged felt
		# wrong): the hold FIRES THE MOMENT it reaches the threshold -- see
		# _physics_process -- forgetting the checkpoint and respawning at the
		# level's own spawn. Releasing earlier is a tap: the plain respawn.
		if event.pressed:
			_r_pressed_at_ms = Time.get_ticks_msec()
		elif _r_pressed_at_ms >= 0:
			_r_pressed_at_ms = -1
			reset_player()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_K:
			# DEBUG. Routed through died_from_fall rather than reset_player()
			# so it exercises the real chain -- cutscene, then respawn --
			# which is the thing worth being able to trigger on demand.
			if player != null:
				player.died_from_fall.emit()

## Blends the WorldEnvironment's ambient light between neutral and the cold
## tint every frame, reading CameraConfig.ambient_cold_strength off `config`
## -- see that field's own comment for why a level-side dial lives on a
## player-side config. Re-applied continuously, not just once in _ready(),
## for the same reason CameraRig re-applies its own fields every frame: so
## dragging the F1 slider changes what is on screen immediately, not only
## after a reload.
func _process(_delta: float) -> void:
	if _world_environment == null or _world_environment.environment == null or config == null:
		return
	var strength: float = clampf(config.camera.ambient_cold_strength, 0.0, 1.0)
	_world_environment.environment.ambient_light_color = \
			NEUTRAL_AMBIENT_TINT.lerp(COLD_AMBIENT_TINT, strength)
	_apply_fog(_world_environment.environment)

## Drives both of the Environment's fogs from this level's own FogConfig, every
## frame, for the same reason the ambient tint above is re-applied every frame:
## so dragging the F1 slider changes what is on screen NOW, not after a reload.
##
## A null `fog` returns without touching anything -- see the export's comment.
## That is not the same as `enabled = false`, which actively turns both fogs
## OFF; the difference is "this level does not manage fog" versus "this level
## manages fog and wants none".
func _apply_fog(environment: Environment) -> void:
	if fog == null:
		return
	if not fog.enabled:
		environment.fog_enabled = false
		environment.volumetric_fog_enabled = false
		return

	environment.fog_enabled = true
	# DEPTH, not the EXPONENTIAL default: only this mode has begin/end
	# distances, and "start fading at 60 m" is the whole request.
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = fog.tint
	environment.fog_density = clampf(fog.max_opacity, 0.0, 1.0)
	environment.fog_depth_begin = fog.fade_begin_distance
	# NEVER exactly the begin distance, and never 0. Godot reads fog_depth_end
	# == 0 as "use the camera's far plane", so a dial dragged to zero would
	# silently jump the curtain out to 4000 m instead of pulling it in; and an
	# end at or below the begin is a division by a non-positive span inside the
	# fog shader. Clamping to a hair beyond the begin gives the hard wall that
	# dragging end below begin honestly deserves, with no special case.
	environment.fog_depth_end = maxf(fog.fade_end_distance, fog.fade_begin_distance + MIN_FOG_FADE_SPAN)
	environment.fog_sky_affect = FOG_SKY_AFFECT
	# A DIAL, not the constant this used to be -- see FogConfig.sky_blend for
	# the bug that made it one: at the old hardcoded 0.6 a fog tint set to pure
	# white came out grey, because what it was blending toward is the default
	# sky's grey horizon.
	environment.fog_aerial_perspective = clampf(fog.sky_blend, 0.0, 1.0)

	# NOT `density > 0.0`. A level is allowed to run the froxel grid at zero
	# global density so that its FogVolumes -- dust hanging in a light shaft,
	# and nowhere else -- are the only thing in it; Godot's own documentation
	# names that setup. Tying the switch to the density would make it
	# unreachable and take every FogVolume down with it, silently.
	environment.volumetric_fog_enabled = fog.volumetric_enabled
	environment.volumetric_fog_density = fog.volumetric_density
	# Never 0: Godot divides the froxel grid across this distance, and a level
	# whose slider is mid-drag through zero must degrade to "very short" rather
	# than to a division by nothing.
	environment.volumetric_fog_length = maxf(fog.volumetric_distance, MIN_VOLUMETRIC_DISTANCE)
	environment.volumetric_fog_ambient_inject = maxf(fog.volumetric_ambient_inject, 0.0)

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
	if not is_instance_valid(player):
		return
	# The R hold coming due: trigger NOW, not on release, and mark the press
	# consumed so the eventual keyup does nothing further.
	if _r_pressed_at_ms >= 0 \
			and Time.get_ticks_msec() - _r_pressed_at_ms >= int(CHECKPOINT_CLEAR_HOLD * 1000.0):
		_r_pressed_at_ms = -1
		restart_from_spawn()
	# ⚠️ THE RAGDOLL IS THE ONE THAT FALLS. ✅ The owner: "falling past z = -20
	# no longer resets -- it makes me watch six seconds of ragdoll."
	#
	# Exactly so: once the ragdoll takes over, the capsule STOPS (see
	# FallUncontrolledMove), so its own Y never crosses this line again and the
	# only thing left to end the fall was the settle timeout. The body that is
	# actually falling is the one to ask.
	var depth: float = player.global_position.y
	if player.ragdoll != null and player.ragdoll.is_simulating():
		depth = player.ragdoll.hips_position().y
	if depth < -config.pawn.fall_recovery_depth:
		reset_player()

## The R-hold action, also reachable from the pause menu's 重新开始: forget
## the checkpoint and respawn at the level's own spawn. Under the curtain --
## ✅ the owner: the bare teleport was 突兀. The clear and the reset both
## happen at full cover.
func restart_from_spawn() -> void:
	if not is_instance_valid(player):
		return
	if _death_sequence != null:
		_death_sequence.cover_respawn(player, func() -> void:
			player.active_checkpoint = null
			reset_player())
	else:
		player.active_checkpoint = null
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
	# ⚠️ THE BODY COMES BACK BEFORE THE PLAYER DOES. ✅ The owner: "the order is
	# wrong -- put the ragdoll back before respawning, or the player gets
	# launched the moment they come back."
	#
	# stop() above already does it on every route that goes through the
	# sequence, and this is the belt to that brace: a ragdoll started by
	# FallUncontrolledMove can outlive a sequence that was never playing (the R
	# key mid-fall), and teleporting a body whose bones are still being solved
	# is exactly the launch they saw. Idempotent -- stop() on a ragdoll that is
	# not simulating does nothing.
	if player.ragdoll != null:
		player.ragdoll.stop()
	# The curtain the death drew, lifted on the far side of the respawn -- see
	# DeathSequence.BLACKOUT. Cleared HERE rather than by the sequence, because
	# the whole point is that it outlasts the sequence: the body has to be back
	# on its feet before the screen comes up.
	if player.screen_effects != null:
		player.screen_effects.set_tint(player.screen_effects.tint_color(), 0.0)
	player.velocity = Vector3.ZERO
	# The last-touched checkpoint outranks the level's spawn point --
	# position and facing both. Wake up where the trigger stands, looking
	# down its -Z.
	var checkpoint: Checkpoint = player.active_checkpoint
	if checkpoint != null and is_instance_valid(checkpoint):
		# Origin = BODY CENTRE, the same convention SpawnPoint has always
		# used -- ✅ the owner tried feet-at-origin first and chose
		# consistency instead ("和spawnpoint保持一致更好，不然会让我疑惑").
		# The editor gizmo hangs the capsule around the node accordingly.
		player.global_position = checkpoint.global_position
		player.rotation = Vector3(0.0, checkpoint.global_rotation.y, 0.0)
	else:
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
