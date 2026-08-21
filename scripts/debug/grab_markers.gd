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

## ⚠️ Debug-only sizes.
const MARKER_RADIUS := 0.06
const NORMAL_LENGTH := 0.6

var _edge: MeshInstance3D
var _hang: MeshInstance3D
var _normal: MeshInstance3D

func _ready() -> void:
	_edge = _make_ball(Color(1.0, 0.1, 0.1))
	_hang = _make_ball(Color(1.0, 0.9, 0.1))
	_normal = _make_spar(Color(0.3, 0.6, 1.0))

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
	if player == null or player.probes == null or _edge == null:
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
