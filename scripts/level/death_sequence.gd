class_name DeathSequence
extends Node

# ⚠️ Every number here is project-defined. The original plays a cutscene at
# this point and its data says nothing about camera timing.
#
# Owned by the level rather than by a Move, because by the time this runs the
# body has no state left to be in -- see spec §1 on the two orthogonal state
# machines.

signal finished

const DROP_TIME := 0.35     ## eye height -> half crouch
const HOLD_TIME := 0.35     ## a beat on the ground before toppling
const TOPPLE_TIME := 0.70   ## quarter circle to the left, pivoting on the feet

var _player: Player
var _elapsed: float = 0.0
var _playing: bool = false
var _eye_height: float = 0.0

func total_duration() -> float:
	return DROP_TIME + HOLD_TIME + TOPPLE_TIME

func play(player: Player) -> void:
	_player = player
	_elapsed = 0.0
	_playing = true
	if _player != null:
		# config is only absent for a bare Player.new() that skipped setup()
		# (some headless tests do exactly that); guard it the same way the
		# camera_rig/screen_effects calls below are guarded, rather than
		# assuming a live Player always has one.
		if _player.config != null:
			_eye_height = _player.config.camera.eye_height
		if _player.camera_rig != null:
			_player.camera_rig.begin_cinematic()
		if _player.screen_effects != null:
			_player.screen_effects.set_desaturation(1.0)
		_player.lock_input()

func _physics_process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _player != null and _player.camera_rig != null:
		var pose := _pose_at(_elapsed)
		_player.camera_rig.set_cinematic_pose(pose[0], pose[1])
	if _elapsed >= total_duration():
		_release_player()
		finished.emit()

## Cancels a sequence in progress. The level calls this whenever it respawns by
## some other route (the manual reset key), because a sequence left running
## would fire `finished` -- and therefore a second respawn -- long after the
## player got on with their life.
##
## Deliberately does NOT emit `finished`: this is a cancellation, not a
## completion, and Arena wires `finished` straight to reset_player(), which is
## the very thing being cancelled. Safe to call at any time -- on a sequence
## that never started, or from inside the `finished` handler itself (by then
## _release_player() has already cleared _playing, so this returns immediately
## and the finished -> reset_player -> stop chain cannot recurse).
func stop() -> void:
	if not _playing:
		return
	_release_player()

## Everything a sequence owes the player on its way out, shared by the normal
## end above and by stop() so the two cannot drift apart: the camera comes back
## from cinematic, the screen loses the death desaturation, and the input gate
## opens. Whether `finished` fires is the CALLER's business, and is the only
## thing that separates finishing from being cancelled.
func _release_player() -> void:
	_playing = false
	if _player == null:
		return
	if _player.camera_rig != null:
		_player.camera_rig.end_cinematic()
	if _player.screen_effects != null:
		_player.screen_effects.set_desaturation(0.0)
	_player.unlock_input()

## Local camera offset and roll at time t. Returns [Vector3, float].
func _pose_at(t: float) -> Array:
	var half: float = _eye_height * 0.5
	if t < DROP_TIME:
		# Ease-out: the legs give way fast, then settle.
		var k: float = 1.0 - pow(1.0 - (t / DROP_TIME), 2.0)
		return [Vector3(0.0, lerpf(_eye_height, half, k) - _eye_height, 0.0), 0.0]
	if t < DROP_TIME + HOLD_TIME:
		return [Vector3(0.0, half - _eye_height, 0.0), 0.0]
	var k2: float = clampf((t - DROP_TIME - HOLD_TIME) / TOPPLE_TIME, 0.0, 1.0)
	# Pivot on the feet: the head sweeps a quarter circle of radius `half`
	# rather than sliding sideways at a fixed height.
	var angle: float = k2 * PI * 0.5
	var y: float = half * cos(angle) - _eye_height
	var x: float = -half * sin(angle)
	return [Vector3(x, y, 0.0), -angle]
