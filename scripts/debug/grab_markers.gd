class_name GrabMarkers
extends Node3D

# Draws what the ledge probe is currently seeing, so a grab that goes somewhere
# unexpected can be diagnosed by looking at it rather than by reading numbers
# off the HUD and trying to picture them.
#
# Three markers, all unshaded so they read against any surface:
#
#   RED     the edge the probe found -- a point on the ledge's TOP, which is
#           NOT the same as the wall's face and is exactly the distinction that
#           has caused two bugs here already
#   YELLOW  where the body would end up hanging, if a reach started now
#   BLUE    a short spar out along the wall's normal, from the edge, showing
#           which way "square to the wall" points
#
# Queried live every frame, not only while grabbing: seeing what the probe
# thinks about a ledge BEFORE jumping at it is most of the value.

## Assigned by Arena. Optional so nothing breaks without one.
@export var player: Player

## DEBUG-ONLY SIZES.
const MARKER_RADIUS := 0.06
const NORMAL_LENGTH := 0.6

var _edge: MeshInstance3D
var _hang: MeshInstance3D
var _normal: MeshInstance3D

func _ready() -> void:
	_edge = _make_ball(Color(1.0, 0.1, 0.1))
	_hang = _make_ball(Color(1.0, 0.9, 0.1))
	_normal = _make_spar(Color(0.3, 0.6, 1.0))
	# The group is the whole registration: the tuning panel finds every overlay
	# through it and duck-types the two methods below.
	add_to_group("debug_overlay")

## OFF UNTIL ASKED FOR. These are diagnostic lines drawn every frame in front
## of whatever is being played, and drawn unconditionally they are noise sitting
## on top of the level -- the probe's opinion about a ledge is worth seeing
## while a grab is being debugged and worth nothing the rest of the time.
##
## Shares F12 with the scripted path and the other probe overlays: they answer
## the same kind of question, and one key for "show me what the probes think"
## beats three to remember.
var _shown: bool = false

## Turns the markers on or off from code. Mirrors CapsuleDebug.show_overlay()
## and the rest of the debug_overlay group -- the tuning panel's Debug page
## duck-types this without knowing the class.
func show_overlay(on: bool) -> void:
	_shown = on
	if not on:
		_hide_markers()

## Duck-typed getter the Debug page reads every frame to keep its checkbox in
## step with the keyboard toggle.
func overlay_shown() -> bool:
	return _shown

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo 			and event.physical_keycode == KEY_F12:
		show_overlay(not _shown)

func _hide_markers() -> void:
	if _edge == null:
		return
	_edge.visible = false
	_hang.visible = false
	_normal.visible = false

func _make_ball(colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = MARKER_RADIUS
	ball.height = MARKER_RADIUS * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	node.mesh = ball
	node.material_override = _unshaded(colour)
	node.visible = false
	add_child(node)
	return node

func _make_spar(colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, NORMAL_LENGTH)
	node.mesh = box
	node.material_override = _unshaded(colour)
	node.visible = false
	add_child(node)
	return node

## Unshaded and drawn on top, so a marker inside geometry is still visible --
## which is the case that matters, since "the hang point is inside the wall" is
## one of the things this exists to show.
func _unshaded(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.no_depth_test = true
	return material

func _process(_delta: float) -> void:
	if not _shown or player == null or player.probes == null or _edge == null:
		return
	var hit: Dictionary = player.probes.ledge_query()
	if not hit.get("valid", false):
		_edge.visible = false
		_hang.visible = false
		_normal.visible = false
		return

	var edge: Vector3 = hit["edge"]
	_edge.global_position = edge
	_edge.visible = true

	# The same pose the reach would aim for, computed by the reach's own code
	# rather than a copy of it -- a marker that drifts from the behaviour it
	# illustrates is worse than no marker.
	_hang.global_position = IntoGrabMove.hanging_pose(player, player.config, hit)
	_hang.visible = true

	var face_normal: Vector3 = hit.get("face_normal", Vector3.ZERO)
	face_normal.y = 0.0
	if face_normal.length_squared() > 0.0001:
		face_normal = face_normal.normalized()
		_normal.global_position = edge + face_normal * (NORMAL_LENGTH * 0.5)
		_normal.look_at(edge + face_normal * NORMAL_LENGTH, Vector3.UP)
		_normal.visible = true
	else:
		_normal.visible = false
