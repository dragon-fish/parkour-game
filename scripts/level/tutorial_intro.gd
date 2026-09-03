class_name TutorialIntro
extends Node

# The tutorial's opening shot, and the hand-over out of it.
#
# THIS IS THE REAL PLAYER, NOT A PICTURE OF ONE. The main menu shows a body
# instanced into a SubViewport with a camera of its own, which is why getting
# from that shot into the game needs a scene swap and a curtain over it. Here
# the crouched figure IS the Player and the lens IS her CameraRig, parked, so
# standing up, the camera coming round behind her and control arriving are one
# continuous shot with no load, no swap and nothing that blanks the screen.
# DO NOT reintroduce a transition anywhere in this file.
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

## The body being filmed. Without one this node hands over immediately, so a
## level that forgot to wire it is playable rather than frozen.
@export var player: Player

## Seconds the stand-up and the camera move take. They are ONE beat: the body
## reaches fully standing on the frame the camera lands.
@export var rise_time: float = 1.5

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
var _anim_tree: AnimationTree
var _anim_player: AnimationPlayer

## True until control reaches the player -- from before the first tick, through
## the held shot and the rise, up to the frame `handed_over` fires.
func is_holding() -> bool:
	return _state != _State.DONE

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
				_start_stand_up()
			# Cubic ease-in-out, the shape the menu's own rise uses.
			_pose(k * k * (3.0 - 2.0 * k) if k < 1.0 else 1.0)
			if k >= 1.0:
				_hand_over()

func _unhandled_input(event: InputEvent) -> void:
	if _state != _State.HELD:
		return
	var pressed_key: bool = event is InputEventKey \
		and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var clicked: bool = event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed
	if not (pressed_key or clicked):
		return
	_state = _State.RISING
	_elapsed = 0.0

func _begin_shot() -> void:
	player.lock_input()
	var rig: CameraRig = player.camera_rig
	_seat = rig.camera.position if rig.camera != null else Vector3.ZERO
	_rest = rig.position
	_base_fov = player.config.camera.fov_base
	rig.begin_cinematic()
	_hold_the_crouch()
	_state = _State.HELD
	_pose(0.0)
	# APPLIED ON THIS TICK, not left for the next one. The Player runs before
	# this node and has already placed the rig for the ordinary view; without
	# this the level's first frame is drawn from behind her and the shot cuts in
	# afterwards. Player itself calls update_effects the same way with a zero
	# delta -- in the cinematic branch it only copies the pose across.
	rig.update_effects(0.0, 0.0, player.grounded)

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
	if player != null:
		if player.camera_rig != null:
			player.camera_rig.end_cinematic()
		player.unlock_input()
	if _anim_tree != null:
		# THE TREE MUST BE THE ONLY WRITER AGAIN. Reactivating it is not enough:
		# a clip started with AnimationPlayer.play() keeps applying its own
		# tracks to the same skeleton, and whatever the move machine blends is
		# overwritten by it every frame. The body then holds the crouch through
		# every move the player makes, which reads as an animation-less
		# character rather than as two things fighting.
		if _anim_player != null:
			_anim_player.stop()
		_anim_tree.active = true
	set_physics_process(false)
	handed_over.emit()

# ---------------------------------------------------------------------------
# The body's own animation. The mounted body is driven by an AnimationTree
# whose states come from the move machine, and there is no move for "posing for
# an opening shot" -- so the tree steps aside for the length of the shot and
# the body's AnimationPlayer is driven directly, the way the main menu drives
# its own bare silhouette. NO BODY, NO PROBLEM: body_scene is optional and all
# of this no-ops when nothing is mounted.
# ---------------------------------------------------------------------------

## The clips this shot asks for by name, in the tiers the free asset set
## actually ships. Crouch_Exit is a real stand-up -- weight shifts, a hand
## leaves the floor -- and ships only in the paid tier; the Idle blend is what
## a checkout without it gets, and it reads as the body inflating rather than
## pushing off.
const CROUCH_CLIP := &"Crouch_Idle"
const STAND_UP_CLIP := &"Crouch_Exit"
const STANDING_CLIP := &"Idle"

func _hold_the_crouch() -> void:
	_anim_tree = player.get_node_or_null("BodyRoot/AnimationTree") as AnimationTree
	if _anim_tree == null:
		return
	# The tree already knows which AnimationPlayer it drives; asking it beats
	# searching the body for one that may not be the same node.
	_anim_player = _anim_tree.get_node_or_null(_anim_tree.anim_player) as AnimationPlayer
	if _anim_player == null:
		_anim_tree = null
		return
	_anim_tree.active = false
	if _anim_player.has_animation(CROUCH_CLIP):
		_anim_player.play(CROUCH_CLIP)
	elif _anim_player.has_animation(STANDING_CLIP):
		_anim_player.play(STANDING_CLIP)

## When to START standing so the body finishes WITH the camera. A real
## Crouch_Exit is shorter than the window it fills, so it begins late --
## stretching it to fill rise_time instead plays a 0.83 s motion at 0.55x and
## reads as wading through treacle.
func _stand_up_delay() -> float:
	if _anim_player != null and _anim_player.has_animation(STAND_UP_CLIP):
		return maxf(rise_time - _anim_player.get_animation(STAND_UP_CLIP).length, 0.0)
	return 0.0

func _start_stand_up() -> void:
	if _anim_player == null:
		return
	if _anim_player.has_animation(STAND_UP_CLIP):
		_anim_player.play(STAND_UP_CLIP)
		# Its last frame IS the standing pose, so Idle follows with no blend.
		_anim_player.queue(STANDING_CLIP)
		return
	if _anim_player.has_animation(STANDING_CLIP):
		_anim_player.play(STANDING_CLIP, rise_time)
