class_name TutorialIntro
extends Node

# The tutorial's opening shot, and the hand-over out of it.
#
# THE FIGURE IN THE SHOT IS NOT THE PLAYER. She is a SilhouetteBody: a bare
# model with its own AnimationPlayer and nothing else writing her bones. The
# real Player stands in the same spot with her body hidden and her input
# locked, and the two are swapped on the frame the stand-up ends -- both are
# the same red silhouette in the same place, so the cut is not visible.
#
# THIS IS A DECEPTION AND IT IS ALLOWED TO BE ONE. Posing the real Player was
# tried and it does not work: her skeleton has an AnimationTree fed by the move
# machine, a HeadLook modifier turning the neck toward the lens every frame,
# clip-offset drivers and spring bones on it, and silencing them one at a time
# means the one that gets missed is on screen -- a neck twisted toward a
# side-on camera, and a body stuck in the crouch clip through every move made
# afterwards. Both of those shipped. DO NOT bring the AnimationTree, the
# modifiers or AnimationPlayer.play() on the real body back into this file.
#
# NOTHING CUTS AND NOTHING COVERS. The camera is the Player's own rig, parked,
# so standing up, the lens coming round behind her and control arriving are one
# continuous shot inside one scene -- no load, no swap, no curtain. DO NOT
# reintroduce a transition anywhere in this file.
#
# THE PLAYER IS NOT SET UP WHEN THIS NODE IS READY. A child's _ready() runs
# before its parent's, so Arena._ready() has not yet called player.setup() and
# there is no move manager, no config and no mounted body to reach for. Every
# reach into the Player happens from _physics_process instead, on the first
# tick that finds it built -- the same trap TutorialDirector already fell into.
#
# AND IT RUNS AFTER THE PLAYER IN TREE ORDER, deliberately: CameraRig's own
# update_effects() must have run once before the cutscene freezes it, or the
# camera child is left at the origin and the body is left rendering both of its
# layer variants at once.

## The body whose place the stand-in takes and whose camera films it. Without
## one this node hands over immediately, so a level that forgot to wire it is
## playable rather than frozen.
@export var player: Player

## Seconds the stand-up and the camera move take. They are ONE beat: the body
## reaches fully standing on the frame the camera lands. Keep it equal to
## MainMenu.RISE_TIME -- the two openings are the same move.
@export var rise_time: float = 1.5

## The blend the stand-up falls back to when the model has no real Crouch_Exit
## clip. Same value and same reason as MainMenu.BODY_STAND_BLEND.
@export var stand_blend: float = 1.5

## The held shot, in the body's own frame, measured from its origin (the
## capsule's centre, ~0.95 m off the floor).
##
## PLACEHOLDERS. Nothing here can be solved -- the figure's height depends on
## whichever model is mounted, and whether the framing reads is a matter for
## the eye. These put the lens off her right shoulder at roughly the main
## menu's close-up: profile, head towards screen right, filling most of the
## frame.
@export var shot_right: float = 1.3
@export var shot_height: float = -0.10
@export var shot_forward: float = -0.11
## Where the lens points, degrees in the body's frame. 90 looks along the
## body's own -X, i.e. straight at her from her right, which puts her head
## towards screen right the way the menu's opening plate does.
@export var shot_yaw_degrees: float = 90.0
@export var shot_pitch_degrees: float = 0.0
## The close-up's field of view. The game's own fov_base is far wider -- a
## portrait framed at it would want the lens close enough to clip through her.
@export var shot_fov_degrees: float = 55.0

## Emitted the instant control reaches the player. LevelZero starts the
## tutorial's own beats off this rather than off its _ready(), so nothing is
## said over a shot the player cannot act in.
signal handed_over

## Above ScreenEffects (100) so nothing the camera does can wash the mark out,
## and below PauseUi (200) so Esc still puts a menu over the whole thing.
const PLATE_LAYER := 150

enum _State { WAITING, HELD, RISING, DONE }

var _state: int = _State.WAITING
var _elapsed: float = 0.0
var _stood_up: bool = false
## Where the ordinary third-person camera sits, captured the tick the shot
## takes over. The rise ends exactly there, so handing the rig back is not a
## cut -- see _pose().
var _seat: Vector3 = Vector3.ZERO
## Where the rig itself rests, captured on the same tick as _seat. The blend
## ends HERE rather than at the rig's nominal eye position: the resting spot
## also carries the eye's forward offset and the head-follow, and a rise that
## ignored those would step ~0.2 m sideways on the frame control arrives.
var _rest: Vector3 = Vector3.ZERO
var _base_fov: float = 90.0

## The stand-in. Null on a machine with no body linked, which is a shot with
## nobody in it and still a level that hands over control.
var performer: SilhouetteBody

var _plate_layer: CanvasLayer
var _plate: MeOpeningPlate

## True until control reaches the player -- from before the first tick, through
## the held shot and the rise, up to the frame `handed_over` fires.
func is_holding() -> bool:
	return _state != _State.DONE

# THE MARK IS UP FROM THE FIRST FRAME, which is why it is built here and not
# on the tick the shot begins. The router that launched this level shows a bare
# ground and no mark of its own precisely so that this one can be the only one
# on screen; a mark that waited for the player to finish setting up would be
# the flash-and-vanish that started this rework.
func _ready() -> void:
	_plate_layer = CanvasLayer.new()
	_plate_layer.name = "OpeningPlate"
	_plate_layer.layer = PLATE_LAYER
	add_child(_plate_layer)
	_plate = MeOpeningPlate.new()
	_plate_layer.add_child(_plate)
	_plate.open()

func _physics_process(delta: float) -> void:
	if _state == _State.DONE:
		return
	if player == null or player.camera_rig == null:
		_hand_over()
		return
	# The mark that Arena._ready() has been through: setup() is what builds the
	# move manager and gives the rig its config.
	if player.move_manager == null or player.config == null:
		return

	match _state:
		_State.WAITING:
			_begin_shot()
		_State.HELD:
			# EVERY TICK, not once. Player.reset_state() clears the lock, and
			# Arena calls it on any respawn -- including one that lands while
			# the shot is still held.
			player.lock_input()
			_pose(0.0)
		_State.RISING:
			_elapsed += delta
			var k: float = clampf(_elapsed / maxf(rise_time, 0.001), 0.0, 1.0)
			if not _stood_up and _elapsed >= _stand_up_delay():
				_stood_up = true
				if performer != null:
					performer.start_stand_up(stand_blend)
			# Cubic ease-in-out, the shape the menu's own rise uses.
			_pose(k * k * (3.0 - 2.0 * k) if k < 1.0 else 1.0)
			if k >= 1.0:
				_hand_over()

func _unhandled_input(event: InputEvent) -> void:
	if _state != _State.HELD:
		return
	# THE SAME GATE THE MENU USES: a press during the opening hold, before the
	# invitation is on screen, is not an answer to anything.
	if _plate != null and not _plate.prompt_shown:
		return
	var pressed_key: bool = event is InputEventKey \
		and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var clicked: bool = event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed
	if not (pressed_key or clicked):
		return
	_state = _State.RISING
	_elapsed = 0.0
	if _plate != null:
		_plate.dismiss()

func _begin_shot() -> void:
	player.lock_input()
	var rig: CameraRig = player.camera_rig
	_seat = rig.camera.position if rig.camera != null else Vector3.ZERO
	_rest = rig.position
	_base_fov = player.config.camera.fov_base
	rig.begin_cinematic()
	_raise_performer()
	_state = _State.HELD
	_pose(0.0)
	# APPLIED ON THIS TICK, not left for the next one. The Player runs before
	# this node and has already placed the rig for the ordinary view; without
	# this the level's first frame is drawn from behind her and the shot cuts in
	# afterwards. Player itself calls update_effects the same way with a zero
	# delta -- in the cinematic branch it only copies the pose across.
	rig.update_effects(0.0, 0.0, player.grounded)

func _stand_up_delay() -> float:
	return performer.stand_up_delay(rise_time) if performer != null else 0.0

## Places the lens for a blend factor k: 0 is the held profile, 1 is exactly
## where the ordinary third-person camera sits, so end_cinematic() lands on the
## frame the rig would have drawn anyway.
func _pose(k: float) -> void:
	var rig: CameraRig = player.camera_rig
	var shot := Vector3(shot_right, shot_height, -shot_forward)
	# What set_cinematic_pose takes is an offset from the rig's nominal eye
	# position, so every absolute point above is converted here rather than
	# being authored in the rig's own terms.
	var base := Vector3(0.0, player.config.camera.eye_height, -rig.eye_forward)
	rig.set_cinematic_pose(shot.lerp(_rest, k) - base, 0.0,
		deg_to_rad(shot_pitch_degrees) * (1.0 - k))
	rig.set_cinematic_yaw(deg_to_rad(shot_yaw_degrees) * (1.0 - k))
	if rig.camera != null:
		# The camera CHILD carries the third-person seat, and the rig's own yaw
		# swings it round while the shot is coming out of profile. Zero at the
		# held end so the lens sits where this node put it, and full at the
		# other so nothing moves when the rig takes over again.
		rig.camera.position = _seat * k
		rig.camera.fov = lerpf(shot_fov_degrees, _base_fov, k)

func _hand_over() -> void:
	if _state == _State.DONE:
		return
	_state = _State.DONE
	_dismiss_performer()
	if _plate_layer != null:
		_plate_layer.queue_free()
		_plate_layer = null
		_plate = null
	if player != null:
		if player.camera_rig != null:
			player.camera_rig.end_cinematic()
		player.unlock_input()
	set_physics_process(false)
	handed_over.emit()

# ---------------------------------------------------------------------------
# The stand-in
# ---------------------------------------------------------------------------

## Stands the performer exactly where the Player's own body is drawn, and takes
## that body off screen for as long as she is there.
##
## THE ORIGIN CONVENTION IS FEET, HERS AND THE MOUNT'S. Player mounts its body
## at compute_mount_transform(), which drops the capsule's centre by half its
## height before adding the profile's own offset; SilhouetteBody applies the
## same offset from its own origin. So dropping this node by half a capsule
## puts the two models in the same place to the millimetre. DO NOT add the
## profile's mount_offset here as well -- the stand-in has already applied it.
func _raise_performer() -> void:
	performer = SilhouetteBody.build()
	if performer == null:
		return
	var host: Node = player.get_parent()
	if host == null:
		host = self
	host.add_child(performer)
	var stance: Transform3D = player.global_transform
	stance.origin.y -= player.current_capsule_height() * 0.5
	performer.global_transform = stance
	performer.hold_crouch()
	var body_root: Node3D = player.get_node_or_null("BodyRoot") as Node3D
	if body_root != null:
		body_root.visible = false

## The swap. Both figures are the same red silhouette standing in the same
## spot, so this is a cut nobody sees -- which is the whole trick.
func _dismiss_performer() -> void:
	if player != null:
		var body_root: Node3D = player.get_node_or_null("BodyRoot") as Node3D
		if body_root != null:
			body_root.visible = true
	if performer != null:
		performer.queue_free()
		performer = null
