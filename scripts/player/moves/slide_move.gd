class_name SlideMove
extends Move

# The original's TdMove_Slide, ported. [ME:CONFIRMED decompile N5 §1, emulated]
#
# A plain TdMove: it keeps whatever physics it finds, which is the walking
# physics, and move input is ignored for the whole slide (DisableMovementTime
# -1). So the controller's acceleration is exactly zero, CalcVelocity takes its
# BRAKING path, and the slide friction (FrictionModifier 0.1, the slide scales
# unclamped -- PawnPhysics.walk_friction_modifier()) is all that slows it:
# 0.8/s on the flat, harder uphill, and down a steep enough fall line the
# friction turns negative and the slide speeds up. Nothing in the move adds or
# takes speed except StopMove, which HALVES the velocity on every way out.
#
# Every tick before the physics it re-aims the velocity: the pawn and the
# velocity turn together by a fifth of the view's yaw error per second plus
# 2000 rotation units a second for a held strafe hint, truncated to whole
# units each frame. It aborts to Crouch when the hint is back or the speed
# falls under SlideAbortSpeed -- and, as the original does, carries on running
# the rest of that PrePhysics on the move it has just left.
#
# There is no time limit: SlideAbortTime is never read. No jump out of a slide
# either: the action table has no MA_Jump row for it.

## [ME:CONFIRMED decompile] TdMove_Slide.CanDoMove's 350 uu/s along the facing.
const MIN_FORWARD_SPEED := 350.0 * UU
## UE3 rotation units per radian, 65536 to a turn.
const ROT_UNITS := 65536.0 / TAU

## TdMove_Slide.bGoingInto: the first 0.5 s, during which a stop is deferred.
var going_into: bool = false
## TdMove_Slide.bRequestUncrouch.
var request_uncrouch: bool = false

func _init() -> void:
	avoid_ledges = false
	use_custom_collision = true
	disable_movement_time = -1.0
	# [ME:CONFIRMED decompile] bDisableFaceRotation: the pawn holds its yaw
	# while the view turns (Player.face_rotation()).
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## TdMove_Slide.CanDoMove: not out of a skill roll; at 350 uu/s or more along
## the pawn's facing (a 3D dot); not up a floor rising more than
## MaxFloorInclineZ along the velocity -- downhill is unlimited. It does not
## ask the base, so no RedoMoveTime. A level's slide block is this project's.
func can_do_move() -> bool:
	if player.move_manager.current_name == SKILL_ROLL:
		return false
	if player.velocity.dot(player.facing()) < MIN_FORWARD_SPEED:
		return false
	var vel_dir: Vector3 = PawnPhysics.safe_normal_2d(player.velocity)
	var slope_dir: Vector3 = PawnPhysics.safe_normal_2d(-player.floor_normal)
	var incline: float = sqrt(1.0 - clampf(player.floor_normal.y * player.floor_normal.y, 0.0, 1.0)) \
		* vel_dir.dot(slope_dir)
	if incline > cfg.max_floor_incline_z:
		return false
	if player.statuses != null and player.statuses.is_move_blocked(SLIDE):
		return false
	return true

## TdMove_Slide.CanStopMove: the stop is remembered, and refused while the
## slide is still going in.
func can_stop_move() -> bool:
	request_uncrouch = true
	return not going_into

func enter(_previous: StringName) -> void:
	going_into = true
	request_uncrouch = false
	set_timer(0.5)

## TdMove_Slide.StopMove: Velocity / 2, every time, and the pawn eased round
## to the view over 0.4 s (FaceRotationTimeLeft) rather than snapped to it.
## The stand-up window the presentation reads opens here too.
func exit() -> void:
	player.velocity = player.velocity / 2.0
	player.face_rotation_time_left = 0.4
	player.begin_slide_recovery()

## After the physics. The model lies along the floor it slides on: drawn
## upright on a slope, the legs hang in the air past the lip. This project's
## presentation.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if player.grounded:
		player.body_tilt_normal = player.floor_normal

func on_timer() -> void:
	going_into = false
	if request_uncrouch:
		abort_move()

## TdMove_Slide.AbortMove: SetMove(Crouch).
func abort_move() -> void:
	player.move_manager.set_move(CROUCH)

## TdMove_Slide.ShouldAbort (0x011f8640): the hint back, or under
## SlideAbortSpeed (3D).
func should_abort() -> bool:
	return player.move_action_hint == MAH_DOWN \
		or player.velocity.length_squared() < cfg.slide_abort_speed * cfg.slide_abort_speed

## TdMove_Slide PrePhysics (0x011fdde0). [ME:CONFIRMED emulated]
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.is_dying():
		return
	if should_abort():
		# The abort happens and this function carries on: the velocity re-aim
		# below runs on the move that has just stopped, after its StopMove
		# halved the speed.
		abort_move()
	var error_units: float = -wrapf(player.rotation.y - player.pawn_yaw, -PI, PI) * ROT_UNITS
	var turn_units: int = int(float(delta * 0.2) * float(_normalize16(int(error_units))))
	if player.move_action_hint == MAH_LEFT:
		turn_units += int(delta * -2000.0)
	elif player.move_action_hint == MAH_RIGHT:
		turn_units += int(delta * 2000.0)
	# UE yaw grows clockwise, Godot's counter-clockwise.
	var turn: float = -float(turn_units) / ROT_UNITS
	var v: Vector3 = player.velocity
	var speed2d: float = Vector2(v.x, v.z).length()
	# Rotator(Velocity) keeps the velocity's pitch; |V| becomes the old
	# horizontal speed.
	var pitch: float = atan2(v.y, speed2d)
	var yaw: float = atan2(-v.x, -v.z) + turn
	player.turn_pawn_yaw(turn)
	player.velocity = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * speed2d
	player.can_uncrouch = player.test_can_uncrouch()

## Normalize to the signed 16-bit range, as FRotator::NormalizeAxis does.
static func _normalize16(units: int) -> int:
	var u: int = units & 0xFFFF
	return u - 0x10000 if u > 0x7FFF else u
