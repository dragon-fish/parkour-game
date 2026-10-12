class_name LedgeWalkMove
extends PhysicsMove

# The original's TdMove_LedgeWalk (MOVE_LedgeWalk 30): back to the wall along
# a narrow ledge. [ME:CONFIRMED decompile script TdMove_LedgeWalk.uc;
# PrePhysics 0x0120a530 emulated, N5 §19]
#
# Taken on entering (or standing in) a ledge-walk volume from Walking, Landing
# or Balance. PlayerLedgeWalking turns the stick's strafe past 0.6 into a
# shimmy action and gives no acceleration; the move sets the velocity itself
# every frame -- 80 uu/s along the line (left is along it, right against it),
# capped by the walking physics at SpeedModifier 0.1, i.e. 72 uu/s -- turns
# the pawn to face away from the wall, and pulls the body onto the line at 10
# per second. Jump on a plain ledge is a Jump with 200 uu/s off the wall;
# leaving the volume ends it 0.2 s later, unless it was entered again.
#
# The volume is a LEDGE_WALK InterestLine: front() points AT the wall, so the
# original's WallNormal is -front(); its FloorNormal is taken as straight up.
# Its spline is the original's (MovementSpline), searched every frame from the
# segment the body was on -- a parameter StartMove never resets, so the next
# ledge walk starts its search where the last one left off.

var volume: InterestLine = null
var current_param_on_curve: float = 0.0
var strafe_factor: float = 0.0
var strafe_speed: float = 0.0
var pending_leaving_volume: bool = false
## MinLookConstraint.Pitch, which CheckLedgeWalkType rewrites.
var min_look_pitch: int = MIN_LOOK_PITCH

const MIN_LOOK_PITCH := -14000
const NARROW_MIN_LOOK_PITCH := -6000
const STRAFE_SPEED := 80.0 * UU
const NARROW_RADIUS := 10.0 * UU

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_LEDGE_WALKING
	disable_face_rotation = true
	disable_controller_facing_pawn_yaw_rotation = true
	avoid_ledges = false

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

## WallNormal: out from the wall.
func wall_normal() -> Vector3:
	return -volume.front()

func is_narrow() -> bool:
	return volume != null and volume.narrow_space

## TdMove_LedgeWalk.CanDoMove: from Walking, Landing or Balance.
func can_do_move() -> bool:
	var state: StringName = player.movement_state
	if state == WALKING or state == LANDING or state == BALANCE:
		return td_can_do_move()
	return false

## TdMove_LedgeWalk.StartMove.
func enter(_previous: StringName) -> void:
	_reset_presentation()
	if is_narrow():
		player.set_collision_radius(NARROW_RADIUS)
	var wall_yaw: int = UE.dir_yaw(wall_normal())
	set_look_at_target_angle(0, wall_yaw, 0.5, 0.5)
	set_precise_rotation(wall_yaw, 0.5)
	strafe_factor = 0.0
	var look_pitch: int = 0
	var look_yaw: int = wall_yaw
	var vel_2d: Vector3 = PawnPhysics.safe_normal(player.velocity)
	vel_2d.y = 0.0
	if not is_narrow():
		look_pitch = min_look_pitch + 7000
		set_look_at_target_angle(look_pitch, look_yaw, 0.2)
	else:
		if UE.cross(wall_normal(), vel_2d).y < 0.0:
			look_yaw += get_min_look_constrain_yaw()
		else:
			look_yaw += get_max_look_constrain_yaw()
		if player.horizontal_speed() > 50.0 * UU:
			set_look_at_target_angle(look_pitch, UE.normalize_axis(look_yaw), 0.2)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	pending_leaving_volume = false
	play_slot_anim(&"LedgeInto", 1.0, 0.2, 0.3)
	check_ledge_walk_type()

func check_ledge_walk_type() -> void:
	if volume == null:
		return
	min_look_pitch = NARROW_MIN_LOOK_PITCH if volume.narrow_space else MIN_LOOK_PITCH

func get_min_look_constrain_pitch() -> int:
	return min_look_pitch

## TdMove_LedgeWalk.HandleMoveAction.
func handle_move_action(action: int) -> void:
	if action == MA_JUMP and not is_narrow():
		if player.move_manager.can_do(JUMP):
			player.velocity = player.facing() * 200.0 * UU
			player.move_manager.set_move(JUMP)
		return
	if action != MA_SHIMMY_LEFT and action != MA_SHIMMY_RIGHT:
		strafe_speed = 0.0
	elif action == MA_SHIMMY_LEFT:
		strafe_speed = STRAFE_SPEED
	else:
		strafe_speed = -STRAFE_SPEED

## TdMove_LedgeWalk.UpdateViewRotation: any look input ends the look-at.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	if delta_rot != Vector2i.ZERO:
		abort_look_at_target()
	return super.update_view_rotation(view, dt, delta_rot, now)

func notify_leaving_volume() -> void:
	pending_leaving_volume = true
	set_timer(0.2)

func notify_entering_volume() -> void:
	pending_leaving_volume = false
	set_precise_rotation(UE.dir_yaw(wall_normal()), 0.5)
	check_ledge_walk_type()

func on_timer() -> void:
	if pending_leaving_volume:
		player.move_manager.set_move(WALKING)

## TdMove_LedgeWalk.StopMove.
func exit() -> void:
	player.set_collision_radius(player.default_collision_radius())

## UTdMove_LedgeWalk's native PrePhysics. [ME:CONFIRMED emulated 0x0120a530]
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.move_manager.current_move() != self or volume == null or not is_instance_valid(volume):
		return
	var here: Vector3 = player.global_position
	var spline := MovementSpline.of(volume)
	var found: Array = spline.find_closest(here, int(current_param_on_curve))
	current_param_on_curve = found[1]
	var c: Vector3 = found[0]
	c.y = here.y
	var t: Vector3 = spline.slope_at(current_param_on_curve / float(spline.num_segments))
	var a: Vector3 = UE.cross(t, Vector3.UP)
	var face: Vector3 = PawnPhysics.safe_normal_2d(a * (wall_normal().dot(a) / a.length_squared()))
	var v: Vector3 = PawnPhysics.safe_normal_2d(t) * strafe_speed
	player.velocity = v
	player.acceleration = v
	if not use_precise_rotation:
		player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(face))
	var side: Vector3 = PawnPhysics.safe_normal(UE.cross(face, Vector3.DOWN))
	strafe_factor = v.dot(side)
	player.phys.move_actor((c - here) * delta * 10.0)

## The volume's PawnEnteredVolume, PawnLeavingVolume and PawnUpdate.
func volume_entered(line: InterestLine) -> void:
	volume = line
	notify_entering_volume()
	if player.movement_state != LEDGE_WALK:
		if can_do_move():
			player.move_manager.set_move(LEDGE_WALK)
		else:
			volume = null

func volume_leaving(_line: InterestLine) -> void:
	if player.movement_state == LEDGE_WALK:
		notify_leaving_volume()

func volume_pawn_update(line: InterestLine) -> bool:
	if player.movement_state == LEDGE_WALK:
		return false
	volume = line
	if can_do_move():
		player.move_manager.set_move(LEDGE_WALK)
		return true
	return false

## After the physics: the presentation's turn and the shuffle it watches.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if player.move_manager.current_move() == self:
		_advance_presentation(delta)

## For the animation: -1 left, 0 still, +1 right, in the MODEL's frame --
## mirrored from the pawn's when the model faces the wall.
func shuffle_direction() -> int:
	var dir: int = 0
	if strafe_factor > 0.0:
		dir = 1
	elif strafe_factor < 0.0:
		dir = -1
	return -dir if _faces_wall else dir

# --- this project's presentation -------------------------------------------------
#
# TWO FACINGS, AND THE VIEW DECIDES. The original always backs onto the wall,
# and FIRST person does here, pawn and model both. THIRD person faces it: a
# third-person player walks up to a ledge looking at the wall, a model pinned
# with its back to that wall turns round on the spot the moment it is caught,
# and facing the wall also puts the ordinary camera, behind the view, on the
# open side of the ledge by itself. ONLY THE PRESENTATION TURNS: the pawn keeps
# the original's back-to-the-wall facing in both views, so the shimmy, the jump
# off the wall and the look window it is measured against are the original's.
# In third person the model faces the wall (model_yaw()), the yaw window is
# centred on the wall and widened (look_yaw_centre_offset(),
# look_yaw_half_span()), A/D are mirrored into the pawn's frame so D still goes
# to the screen's right (presented_strafe()), and the shuffle reported to the
# animation is the model's. Switching views mid-ledge turns the model round in
# place (_begin_turn()).

## Which way the MODEL stands on this ledge: facing the wall (third person) or
## with its back to it (first person). Chosen at the catch and re-chosen by a
## turn whenever the view changes.
var _faces_wall: bool = false
## True from the tick a view change asks for the other facing until the model
## has turned round. No travel meanwhile (presented_strafe()), and
## CharacterAnimator plays turn_clip() fitted to the same window.
var _turning: bool = false
var _turn_elapsed: float = 0.0
## The model's yaw when the turn began, and which way round it goes: +1 turns
## LEFT (Godot's yaw grows counter-clockwise), -1 right.
var _turn_from: float = 0.0
var _turn_sign: float = -1.0
## The last way the model actually shuffled, in the MODEL's frame (+1 its
## right), HELD after the key is released: where the third-person head keeps
## looking (head_yaw_override()).
var _last_shuffle: int = 0
## The third-person W/S assist: whether W/S is held, whether this press engaged
## the assist, and which strafe it drives -- all frozen when the key went down.
var _ws_held: bool = false
var _ws_assist_engaged: bool = false
var _ws_assist_sign: float = 0.0

func _wants_to_face_wall() -> bool:
	return player.camera_rig != null and player.camera_rig.in_third_person()

func faces_wall() -> bool:
	return _faces_wall

func _reset_presentation() -> void:
	_faces_wall = _wants_to_face_wall()
	_turning = false
	_turn_elapsed = 0.0
	_last_shuffle = 0
	# THE LATCHES START OVER AT EVERY CATCH: a key held straight through
	# leaving one ledge and catching the next is a fresh press as far as that
	# ledge is concerned.
	_ws_held = false
	_ws_assist_engaged = false
	_ws_assist_sign = 0.0

## The pawn's own facing on the ledge: where its precise rotation is taking it
## while that runs, the pawn's yaw otherwise.
func _pawn_facing_yaw() -> float:
	return UE.godot_yaw(precise_rotation_yaw) if use_precise_rotation else player.pawn_yaw

## Where the model faces, Godot radians: the pawn's facing, turned to the wall
## in third person, and the turn's own sweep while it runs. Read by
## Player._drive_body_yaw().
func model_yaw() -> float:
	if _turning:
		var t: float = clampf(_turn_elapsed / maxf(_ledge_cfg().turn_time, 0.001), 0.0, 1.0)
		return wrapf(_turn_from + _turn_sign * PI * t, -PI, PI)
	return wrapf(_pawn_facing_yaw() + (PI if _faces_wall else 0.0), -PI, PI)

func _ledge_cfg() -> LedgeWalkConfig:
	return cfg as LedgeWalkConfig

## Turns the model round on the spot, over LedgeWalkConfig.turn_time.
##
## TURNS TOWARD THE VIEW: a body that always turned one way looked wrong
## whenever the player was looking the other. The side the view is on when the
## turn begins is the side the face sweeps through, so a third-person head left
## to follow the view keeps looking where the player was looking. Only a view
## dead ahead falls back to the side the body last travelled, on the leading
## foot; right when it has not travelled at all.
func _begin_turn() -> void:
	_faces_wall = not _faces_wall
	_turning = true
	_turn_elapsed = 0.0
	_turn_from = player.visual_yaw()
	var view_off: float = wrapf(player.rotation.y - _turn_from, -PI, PI)
	if absf(view_off) > deg_to_rad(5.0):
		_turn_sign = 1.0 if view_off > 0.0 else -1.0
	else:
		_turn_sign = 1.0 if _last_shuffle < 0 else -1.0
	# A step to the model's right is to its LEFT once it has turned round; the
	# head keeps watching the same direction in the world.
	_last_shuffle = -_last_shuffle

func _advance_presentation(delta: float) -> void:
	if not _turning and _wants_to_face_wall() != _faces_wall:
		_begin_turn()
	elif _turning:
		_turn_elapsed += delta
		if _turn_elapsed >= _ledge_cfg().turn_time:
			_turning = false
	var dir: int = shuffle_direction()
	if dir != 0:
		_last_shuffle = dir

func is_turning() -> bool:
	return _turning

## The pack's own half turn, on the side the model pivots to. Read by
## CharacterAnimator while is_turning().
func turn_clip() -> StringName:
	return &"Turn180_L" if _turn_sign > 0.0 else &"Turn180_R"

## The scripted-fit hook (CharacterAnimator._scripted_fit): while turning, the
## clip is fitted to end with the turn; 0 otherwise.
func scripted_duration() -> float:
	return _ledge_cfg().turn_time if _turning else 0.0

## Playback rate of the shuffle clips, or 0 to leave it to CharacterAnimator's
## speed match. See LedgeWalkConfig.shuffle_clip_scale. The turn clip is
## fitted, not scaled, so it answers 0 while turning.
func clip_time_scale() -> float:
	return 0.0 if _turning else _ledge_cfg().shuffle_clip_scale

## The look window's centre: the wall the model faces in third person, half a
## turn off the pawn's back-to-the-wall facing.
func look_yaw_centre_offset() -> float:
	return PI if _faces_wall else 0.0

## The wider third-person window -- see
## LedgeWalkConfig.third_person_look_yaw_deg. First person answers NAN and
## keeps the original's.
func look_yaw_half_span() -> float:
	if not _wants_to_face_wall():
		return NAN
	return deg_to_rad(_ledge_cfg().third_person_look_yaw_deg) * 0.5

## The stick's strafe as PlayerLedgeWalking should read it, in the PAWN's
## frame. Asked by Player before the strafe becomes a shimmy action.
##   * Facing the wall, the model's right is the pawn's left: mirrored, so D
##     goes to the model's right, which is the screen's right.
##   * Third person: W/S held with the camera looking along the ledge carry
##     the body that way (_resolve_look_assist()).
##   * Nothing travels while the model turns round: the feet are busy.
func presented_strafe(strafe: float, forward: float) -> float:
	_update_look_assist_latch(forward)
	if _turning:
		return 0.0
	var pawn_strafe: float = -strafe if _faces_wall else strafe
	if _ws_assist_engaged:
		pawn_strafe += _ws_assist_sign * forward
	return clampf(pawn_strafe, -1.0, 1.0)

func _update_look_assist_latch(forward: float) -> void:
	var held: bool = absf(forward) > 0.0001
	if held and not _ws_held:
		_resolve_look_assist()
	elif not held:
		_ws_assist_engaged = false
	_ws_held = held

## THIRD PERSON ONLY, and resolved once per press. Gated on how far the camera
## looks off the ledge's normal AXIS, either way along the line: 45 degrees off
## puts sin(45) of the view along the ledge whichever way the model faces. The
## sign is the pawn-frame strafe that moves the body the way the camera looks:
## a shimmy left travels along the spline's slope (handle_move_action()).
func _resolve_look_assist() -> void:
	_ws_assist_engaged = false
	if not _wants_to_face_wall() or volume == null or not is_instance_valid(volume):
		return
	if player.camera_rig.camera == null:
		return
	var view_forward: Vector3 = -player.camera_rig.camera.global_transform.basis.z
	view_forward.y = 0.0
	if view_forward.length_squared() < 0.0001:
		return
	var spline := MovementSpline.of(volume)
	var slope: Vector3 = spline.slope_at(current_param_on_curve / float(spline.num_segments))
	var along: float = view_forward.normalized().dot(PawnPhysics.safe_normal_2d(slope))
	if absf(along) <= sin(deg_to_rad(_ledge_cfg().look_assist_angle_deg)):
		return
	_ws_assist_sign = -signf(along)
	_ws_assist_engaged = true

## Where the head points, radians off the model's facing, or NAN. THIRD PERSON
## ONLY: it watches the way the body last shuffled, and keeps watching after
## the keys are released. In first person the camera follows a head node by
## position, so turning the head would slide the eye. Not while turning round:
## the turn clip owns the whole body. Negated against _last_shuffle: that
## counts +1 for a step to the model's right, and a yaw measured as "view
## minus model facing" counts positive to the LEFT.
func head_yaw_override() -> float:
	if _turning or not _wants_to_face_wall() or _last_shuffle == 0:
		return NAN
	return -float(_last_shuffle) * deg_to_rad(_ledge_cfg().head_turn_deg)

## Where the head's pitch is held, radians, or NAN; third person only. See
## LedgeWalkConfig.head_pitch_deg.
func head_pitch_override() -> float:
	if _turning or not _wants_to_face_wall():
		return NAN
	return deg_to_rad(_ledge_cfg().head_pitch_deg)
