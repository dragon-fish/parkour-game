class_name DeathSequence
extends Node

# ⚠️ Every number here is project-defined. The original plays a cutscene at
# this point and its data says nothing about camera timing.
#
# Owned by the level rather than by a Move, because by the time this runs the
# body has no state left to be in -- see spec §1 on the two orthogonal state
# machines.

signal finished

## ⚠️ All four are project-defined, and all four come from the owner's own
## storyboard rather than from the original -- which plays a cutscene here and
## whose data says nothing about camera timing.
##
## The two HOLDS are the point of the shape: the body arrives, stops, and only
## then gives way, and it lies still afterwards instead of cutting straight to
## a respawn. Without them the whole thing reads as one continuous slump.
const DROP_TIME := 0.5      ## eye height -> half height, the legs going
const HOLD_TIME := 1.0      ## knelt, not yet fallen
const TOPPLE_TIME := 1.5    ## quarter circle to the right, pivoting near the feet
const REST_TIME := 1.0      ## lying still before the level takes over

## ⚠️ PROJECT-DEFINED. How far above the floor the arc bottoms out, so the view
## ends up cheek-to-the-ground rather than inside it -- a camera pivoting on
## the feet exactly would put its near plane through the floor and show the
## underside of the level.
const GROUND_CLEARANCE := 0.15

var _player: Player
var _elapsed: float = 0.0
var _playing: bool = false
var _eye_height: float = 0.0

## Where the FEET are, in the rig's own local space -- i.e. how far below the
## Player origin the ground is. The rig hangs off the Player node, whose origin
## sits at the capsule's CENTRE, so local y = 0 is roughly half a body above
## the floor rather than on it. Without this the topple arc pivoted around the
## capsule centre and bottomed out a half-body short of the ground: the view
## rolled over but never came down, which is not what falling over looks like.
var _feet_offset: float = 0.0

## The pitch the player happened to be looking at when they died, eased out
## over the drop. Watching the ground rush up is the reflex on a fatal fall, so
## without this the whole topple plays from a face-down view.
var _entry_pitch: float = 0.0

func total_duration() -> float:
	return DROP_TIME + HOLD_TIME + TOPPLE_TIME + REST_TIME

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
		# Half the standing capsule, because the Player origin is its centre.
		# standing_height() rather than the live height: the body may already
		# be crouched or sliding when it dies, and the fall should read from
		# where a standing body's feet are.
		_feet_offset = _player.standing_height() * 0.5
		if _player.camera_rig != null:
			# Read BEFORE begin_cinematic(), while rotation.x is still the
			# player's own look.
			_entry_pitch = _player.camera_rig.rotation.x
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
		_player.camera_rig.set_cinematic_pose(pose[0], pose[1], pose[2])
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

## Local camera offset, roll and pitch at time t. Returns [Vector3, float, float].
##
## Everything below is worked in EYE-ABOVE-GROUND terms and converted to a rig
## offset at the end, because the storyboard is drawn from the ground: the view
## drops to half the body's height, holds, then sweeps a quarter circle of that
## same radius pivoting near the feet -- ending flat on the floor, offset to the
## side by as much as it lost in height.
func _pose_at(t: float) -> Array:
	# Ground to eye, which is what "half height" in the storyboard means.
	var stature: float = _feet_offset + _eye_height
	var half: float = stature * 0.5
	if t < DROP_TIME:
		# Ease-out: the legs give way fast, then settle.
		var k: float = 1.0 - pow(1.0 - (t / DROP_TIME), 2.0)
		# Pitch levels out on the same curve, so a player who died looking at
		# their feet is looking level by the time the body settles onto its
		# knees.
		return [Vector3(0.0, _to_offset(lerpf(stature, half, k)), 0.0), 0.0,
			lerpf(_entry_pitch, 0.0, k)]
	if t < DROP_TIME + HOLD_TIME:
		return [Vector3(0.0, _to_offset(half), 0.0), 0.0, 0.0]
	# easeInOutQuint: barely moves at first, collapses through the middle, and
	# arrives soft. A body with nothing left in it gives way slowly, goes over
	# all at once, and does not slap the ground. A plain ease-out starts at its
	# fastest, which reads as being pushed rather than as giving out.
	#
	# Past TOPPLE_TIME the clamp holds this final pose for REST_TIME, which is
	# what makes the body lie still at the end.
	var u: float = clampf((t - DROP_TIME - HOLD_TIME) / TOPPLE_TIME, 0.0, 1.0)
	var k2: float = 16.0 * pow(u, 5.0) if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 5.0) / 2.0
	# A QUARTER CIRCLE, not a slide sideways and not a drop straight down: the
	# head is on the end of a body that pivots at the floor, so it sweeps an arc
	# of radius `radius` -- losing height and gaining offset together, fastest
	# through the middle of the turn.
	#
	# Pivots on a point just ABOVE the feet, so the arc bottoms out at
	# GROUND_CLEARANCE instead of at the floor itself. The radius shrinks to
	# match, which keeps the arc starting exactly where the drop left off.
	#
	# X AND ROLL MUST AGREE. A roll of -angle turns the camera's up axis toward
	# its RIGHT, i.e. the body is going over to the right, so the head has to
	# travel right as well (+X). It used to travel left while rolling right,
	# and the two cancelling out read as the head dropping straight down and
	# the picture rotating around it -- no waist, no volume, just a spin.
	var angle: float = k2 * PI * 0.5
	var radius: float = maxf(half - GROUND_CLEARANCE, 0.01)
	var y: float = _to_offset(GROUND_CLEARANCE + radius * cos(angle))
	var x: float = radius * sin(angle)
	return [Vector3(x, y, 0.0), -angle, 0.0]

## Converts a height ABOVE THE GROUND into the rig-local offset that
## CameraRig.update_effects() adds to its resting eye position.
func _to_offset(above_ground: float) -> float:
	return above_ground - _feet_offset - _eye_height
