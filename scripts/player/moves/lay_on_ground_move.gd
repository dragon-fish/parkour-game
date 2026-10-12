class_name LayOnGroundMove
extends PhysicsMove

# The original's TdMove_LayOnGround, down on the back, ported.
# [ME:CONFIRMED decompile]
#
# Landing puts the body here when it lands backwards (out of a turn in the
# air, hard while moving backwards, or forced by a stumble), with no speed at
# all; this project's KNOCKDOWN status puts it here too (MoveManager). PHYS_
# Falling by its CDO -- the landing that brings it here hands the body to the
# walking physics straight after -- under the PlayerGrabbing controller, so
# the stick is an action every tick and there is no acceleration; the crouched
# collision, FrictionModifier 0.15, no ledge avoidance.
#
# The body stays down until an action says otherwise: a jump, or any action
# with the hint forward, gets up (JumpTurnLandingStand) -- or crouches, with
# no room to stand -- and any action with the hint back rolls backwards up
# off the floor (EvadeRoll, root motion). Either animation's end sets Walking,
# or Crouch without room. A body that arrives with the hint already back
# rolls at once.

## The two get-up animations' lengths, the original's first-person sequences.
## [ME:CONFIRMED anims] JumpTurnLandingStand 1.333 s (no root motion);
## EvadeRoll is RootMotionClip.evade_roll().
const GET_UP_LENGTH := 1.3333

## TdMove_LayOnGround.bIsGettingUpFromGround / bIsDoingBackRoll.
var getting_up: bool = false
var doing_back_roll: bool = false

var _clip: RootMotionClip = null
var _anim_time: float = 0.0
var _anim_length: float = 0.0
var _facing: Vector3 = Vector3.FORWARD
var _elapsed: float = 0.0
## The blow's own tint when a blow or a hard landing put the body here,
## transparent otherwise. This project's presentation.
var _tint: Color = Color(0.0, 0.0, 0.0, 0.0)

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_GRABBING
	avoid_ledges = false
	use_custom_collision = true
	# [ME:CONFIRMED decompile] bDisableFaceRotation: the pawn holds its yaw
	# while the view turns (Player.face_rotation()).
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## Read by CharacterAnimator: the get-up is a different clip from lying.
func is_rising() -> bool:
	return getting_up

func can_do_move() -> bool:
	return td_can_do_move()

func enter(_previous: StringName) -> void:
	getting_up = false
	doing_back_roll = false
	_clip = null
	_anim_time = 0.0
	_anim_length = 0.0
	_elapsed = 0.0
	_tint = player.pending_stagger_tint
	player.pending_stagger_tint = Color(0.0, 0.0, 0.0, 0.0)
	# Declared on entry: a level's knock-down sets this move outside the
	# physics, on a tick the physics does not then run.
	player.set_grounded(player.physics == PHYS_WALKING)
	if player.move_action_hint == MAH_DOWN:
		_get_up_back()
	_drive_camera(1.0)

func exit() -> void:
	getting_up = false
	doing_back_roll = false
	_drive_camera(0.0)
	_drive_tint(0.0)
	# This project's: a body that has just got up is not knocked straight back
	# down by the hazard it is still standing in.
	player.arm_stagger_immunity()

## TdMove_LayOnGround.HandleMoveAction. Every action counts -- the
## PlayerGrabbing controller sends one every tick.
func handle_move_action(action: int) -> void:
	if action == MA_JUMP or player.move_action_hint == MAH_UP:
		if player.can_stand(player.collision_center() + Vector3.UP * 30.0 * UU):
			_get_up()
		else:
			player.move_manager.set_move(CROUCH)
		return
	if player.move_action_hint == MAH_DOWN:
		_get_up_back()

## TdMove_LayOnGround.GetUp: JumpTurnLandingStand, on the spot.
func _get_up() -> void:
	if getting_up:
		return
	getting_up = true
	_anim_time = 0.0
	_anim_length = GET_UP_LENGTH
	reset_camera_look(1.0)

## TdMove_LayOnGround.GetUpBack: EvadeRoll, a backward roll carried by its
## root motion.
func _get_up_back() -> void:
	if getting_up:
		return
	getting_up = true
	doing_back_roll = true
	_clip = RootMotionClip.evade_roll()
	_facing = player.facing()
	_anim_time = 0.0
	_anim_length = _clip.length
	player.use_root_motion(true)
	reset_camera_look(1.0)
	# The roll looks where it is going: 1000 uu ahead of the pawn, 300 down.
	var look_at: Vector3 = player.global_position + player.facing() * 1000.0 * UU
	look_at.y -= 300.0 * UU
	set_look_at_target_location(look_at, 0.4)

func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.root_motion_active and _clip != null:
		player.root_motion_velocity = _clip.world_velocity(_anim_time, delta, _facing)

func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_elapsed += delta
	# The body lies along the floor it is on. This project's presentation.
	if player.grounded and not getting_up:
		player.body_tilt_normal = player.floor_normal
	if not getting_up:
		_drive_camera(1.0)
		_drive_tint(1.0 - clampf(_elapsed / maxf(cfg.tint_fade_time, 0.0001), 0.0, 1.0))
		return
	_anim_time += delta
	_drive_camera(1.0 - clampf(_anim_time / maxf(_anim_length, 0.0001), 0.0, 1.0))
	if _anim_time >= _anim_length:
		_animation_ended()

## TdMove_LayOnGround.OnCustomAnimEnd: Walking with room to stand, Crouch
## without.
func _animation_ended() -> void:
	getting_up = false
	if player.can_stand(player.collision_center() + Vector3.UP * 30.0 * UU):
		player.move_manager.set_move(WALKING)
	else:
		player.move_manager.set_move(CROUCH)

## The eye goes down with the body and comes back up across the get-up, lifted
## clear of the floor in first person. PROJECT-DEFINED presentation
## (CameraConfig.lay_on_ground_eye_lift).
func _drive_camera(down: float) -> void:
	if player.camera_rig == null:
		return
	player.camera_rig.set_crouch_amount(down)
	var inside: float = 1.0 - player.camera_rig.view_blend()
	player.camera_rig.set_death_lift(config.camera.lay_on_ground_eye_lift * down * inside)

## From outside the pitch band flips: the camera hangs behind the rig, so the
## view that would sink the orbit into the floor is looking UP.
func third_person_pitch_limits() -> Vector2:
	return Vector2(-PI, deg_to_rad(cfg.third_person_pitch_max_deg))

func _drive_tint(severity: float) -> void:
	if _tint.a > 0.0 and player.screen_effects != null:
		player.screen_effects.set_tint(_tint, severity)
