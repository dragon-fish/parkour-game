class_name VertigoMove
extends PhysicsMove

# The original's TdMove_Vertigo, the look down over an edge, ported.
# [ME:CONFIRMED decompile N5 §10, N1 §4.2]
#
# Started only by the walking physics' ledge check (PawnPhysics
# _check_for_ledges()): an edge in the step, nothing within 1000 uu below a
# point 70 uu past it, the pawn facing the drop, Walking slower than a run, an
# edge at least 2 uu from the last one, and this CanDoMove. While it runs the
# ledge check holds the body at the edge (a zero delta), and hands back to
# Walking as soon as the edge stops triggering. The view is pulled down to
# -15000 over 0.28 s, and move and look input are ignored for 1.5 s; turning
# more than 8000 units away from the edge ends it. It shares Walking's row of
# the action table.
#
# RedoMoveTime 3.0 is in the CDO and the ini and never asked: CanDoMove does
# not call the base.

## TdMove_Vertigo.LastVertigoEdgePosition: the point past the edge the drop was
## found under.
var last_edge_position: Vector3 = Vector3.ZERO
## TdMove_Vertigo.LastActualVertigoEdgePosition: the edge EdgeCheck found.
var last_actual_edge_position: Vector3 = Vector3.ZERO

## The look-down: pitch -15000 units, reached over 0.28 s.
## [ME:CONFIRMED decompile] SetLookAtTargetAngle(Pitch -15000, 0.28).
const LOOK_DOWN_PITCH := -15000.0 * TAU / 65536.0
const LOOK_DOWN_TIME := 0.28
## UpdateViewRotation's limit on the yaw to the edge, 8000 units.
const EDGE_YAW_LIMIT := 8000.0 * TAU / 65536.0

var _look_from: float = 0.0
var _looking: bool = false

func _init() -> void:
	super._init()
	disable_movement_time = 1.5
	disable_look_time = 1.5

func is_ported() -> bool:
	return true

## TdMove_Vertigo.CanDoMove: the edge in front, and a box of the body's radius
## and 0.7 of its height, 0.2 H above the centre, free for two radii ahead.
func can_do_move() -> bool:
	var loc: Vector3 = player.collision_center()
	var facing: Vector3 = player.facing()
	if (last_edge_position - loc).normalized().dot(facing) < 0.0:
		return false
	var r: float = player.collision_radius()
	var h: float = player.collision_half_height()
	var start: Vector3 = loc + Vector3.UP * (h * 0.2)
	var end: Vector3 = start + facing * r * 2.0
	if player.phys.trace_blocked(end, start, Vector3(r, h * 0.7, r)):
		return false
	return true

func enter(_previous: StringName) -> void:
	_looking = true
	_look_from = 0.0
	if player.camera_rig != null:
		_look_from = float(player.camera_rig.look_debug()["pitch"])
	set_timer(cfg.zoom_out_time)

## OnTimer at ZoomOutTime: the look-at is aborted -- the view stays where it
## was pulled to. The zoom (DefaultFOV - 6 at ZoomRate) is not ported.
func on_timer() -> void:
	_looking = false

func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if _looking and player.camera_rig != null:
		var t: float = clampf((move_active_time + delta) / LOOK_DOWN_TIME, 0.0, 1.0)
		player.camera_rig.set_pitch(lerpf(_look_from, LOOK_DOWN_PITCH, t))
	# TdMove_Vertigo.UpdateViewRotation: turned too far from the edge, walk.
	var to_edge: Vector3 = last_edge_position - player.global_position
	if Vector2(to_edge.x, to_edge.z).length_squared() > 0.0:
		var edge_yaw: float = atan2(-to_edge.x, -to_edge.z)
		if absf(wrapf(edge_yaw - player.pawn_yaw, -PI, PI)) > EDGE_YAW_LIMIT:
			player.move_manager.set_move(WALKING)
