class_name SkillRollMove
extends PhysicsMove

# The original's TdMove_SkillRoll, ported. [ME:CONFIRMED decompile]
#
# Only from Landing: Landing.StartMove sets it when the fall was at least
# SkillRollLandingHeight and the crouch key went down within 0.2 s of the
# touchdown. A TdPhysicsMove under the walking physics (its CDO's default)
# and the PlayerGrabbing controller, with move and look input ignored and the
# velocity zeroed: the body is carried by fallinglandroll's root motion, 3.1 m
# along the facing it landed with over 1.27 s. It does not avoid ledges, and
# a roll that runs off one falls with the root motion still carrying it (its
# own Landed does nothing, and Falling refuses a roll younger than 0.8 s).
# The animation's end hands back to Walking.
#
# The view's tumble -- a full turn of pitch and a dip of the eye -- is this
# project's presentation of the roll's camera, driven from here.

var _clip: RootMotionClip = RootMotionClip.skill_roll()
var _facing: Vector3 = Vector3.FORWARD
var _anim_time: float = 0.0
## How far the view turns over this roll, and where the spin starts: the
## landing's pitch carried in the spin so the gameplay pitch can be level.
var _spin_total: float = 0.0
var _spin_from: float = 0.0

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_GRABBING
	avoid_ledges = false
	# [ME:CONFIRMED decompile] bDisableFaceRotation: the pawn holds its yaw
	# while the view turns (Player.face_rotation()).
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## TdMove_SkillRoll.CanDoMove: the base, then from Landing only.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	return player.move_manager.current_name == LANDING

func enter(_previous: StringName) -> void:
	_anim_time = 0.0
	_facing = player.facing()
	player.use_root_motion(true)
	player.set_ignore_move_input(-1.0)
	player.set_ignore_look_input(-1.0)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	# The presentation: the gameplay pitch goes level at once, and the spin
	# starts from the pitch the body landed with.
	var pitch_at_start: float = 0.0
	if player.camera_rig != null and not player.camera_rig.in_third_person():
		pitch_at_start = float(player.camera_rig.look_debug()["pitch"])
		player.camera_rig.set_pitch(0.0)
	_spin_from = -pitch_at_start
	_spin_total = cfg.camera_spin
	_drive_camera()

func exit() -> void:
	if player.camera_rig != null:
		player.camera_rig.set_roll_spin(0.0)
		player.camera_rig.set_crouch_amount(0.0)

## SkillRoll's Landed: nothing. A roll that left the ground lands as a roll.
func landed(_normal: Vector3) -> void:
	pass

## The root motion, before the physics.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.root_motion_active:
		player.root_motion_velocity = _clip.world_velocity(_anim_time, delta, _facing)

func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_anim_time += delta
	_drive_camera()
	if _anim_time >= _clip.length:
		_animation_ended()

## OnCeaseRelevantRootMotion, which the original fires at the root motion's
## end: input back, the acceleration along the velocity, root motion off,
## Walking. [ME:INFERRED] when the event fires was not read; taken as the
## sequence's end, where OnCustomAnimEnd would set Walking anyway.
func _animation_ended() -> void:
	player.stop_ignore_look_input()
	player.stop_ignore_move_input()
	player.acceleration = PawnPhysics.safe_normal(player.velocity)
	player.use_root_motion(false)
	player.move_manager.set_move(WALKING)

## The tumble: the view goes all the way over, eased at both ends, and the eye
## dips through the middle. PROJECT-DEFINED presentation.
func _drive_camera() -> void:
	if player.camera_rig == null:
		return
	var t: float = clampf(_anim_time / maxf(_clip.length, 0.001), 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	player.camera_rig.set_roll_spin(lerpf(_spin_from, _spin_total, eased))
	player.camera_rig.set_crouch_amount(sin(PI * t) * cfg.camera_crouch)
