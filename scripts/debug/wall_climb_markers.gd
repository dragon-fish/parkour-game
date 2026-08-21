class_name WallClimbMarkers
extends Node3D

# Draws what the forward wall probe sees, so "why did that not let me kick up
# it" is answerable by looking rather than by reading numbers off the HUD and
# trying to picture them.
#
# Two things are drawn, and between them they cover every reason a kick can be
# refused:
#
#   BALL at the contact point, COLOURED BY VERDICT
#       green   climbable right now -- tall enough, and square enough on
#       yellow  tall enough, but the approach is too oblique: this is a wall
#               RUN, not a climb
#       orange  a wall, but shorter than MinWallHeight -- vault or mantle it
#       (nothing drawn at all means the probe sees no wall)
#
#   SPAR rising from the contact point to WHERE THIS RUN-UP WOULD REACH
#       The climb's height is bought with speed and is worth nothing without
#       it, so the useful question before committing is not "is there a wall"
#       but "how high does what I am carrying get me". The spar answers that
#       live: run faster, or kick earlier in the jump, and watch it grow.
#
# Queried every frame regardless of state, not only while climbing -- seeing
# what the probe thinks about a wall BEFORE jumping at it is most of the value.

## Assigned by Arena. Optional so nothing breaks without one.
@export var player: Player

## ⚠️ Debug-only sizes.
const MARKER_RADIUS := 0.08
const SPAR_THICKNESS := 0.05

const CLIMBABLE := Color(0.2, 1.0, 0.3)
const TOO_OBLIQUE := Color(1.0, 0.9, 0.1)
const TOO_SHORT := Color(1.0, 0.5, 0.1)

var _contact: MeshInstance3D
var _reach: MeshInstance3D

func _ready() -> void:
	_contact = _make_ball()
	_reach = _make_spar()

func _make_ball() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = MARKER_RADIUS
	ball.height = MARKER_RADIUS * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	node.mesh = ball
	node.material_override = _unshaded(Color.WHITE)
	node.visible = false
	add_child(node)
	return node

func _make_spar() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SPAR_THICKNESS, 1.0, SPAR_THICKNESS)
	node.mesh = box
	node.material_override = _unshaded(Color.WHITE)
	node.visible = false
	add_child(node)
	return node

## Unshaded and drawn on top, so a marker inside geometry is still visible --
## which is the case that matters, since a contact point sits ON a wall by
## definition and would otherwise be hidden by it half the time.
func _unshaded(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.no_depth_test = true
	return material

func _tint(node: MeshInstance3D, colour: Color) -> void:
	(node.material_override as StandardMaterial3D).albedo_color = colour

func _hide_all() -> void:
	_contact.visible = false
	_reach.visible = false

func _process(_delta: float) -> void:
	if player == null or player.probes == null or _contact == null:
		return
	var heading := Vector3(player.velocity.x, 0.0, player.velocity.z)
	# Standing still there is no heading to measure an angle against, so the
	# facing stands in. Without this the verdict flickers to "too oblique" the
	# moment the player stops, which is exactly when they are most likely to be
	# stood there looking at the marker trying to understand it.
	if heading.length_squared() < 0.0001:
		heading = -player.global_transform.basis.z
		heading.y = 0.0
	heading = heading.normalized()

	var hit: Dictionary = player.probes.wall_ahead_query(heading)
	if not hit.get("valid", false):
		_hide_all()
		return

	var cfg: WallClimbConfig = player.config.wall_climb
	var square_enough: bool = float(hit["incidence"]) <= cfg.vertical_start_angle
	var tall_enough: bool = bool(hit["tall_enough"])
	var verdict: Color = TOO_SHORT
	if tall_enough:
		verdict = CLIMBABLE if square_enough else TOO_OBLIQUE

	# Reconstructed rather than returned by the probe: the query answers
	# questions about the WALL, and where a ray happened to touch it is this
	# node's business alone.
	var contact: Vector3 = player.global_position - heading * 0.0
	contact += heading * float(hit["distance"])
	contact.y = player.global_position.y + Probes.WALL_AHEAD_CHEST_Y
	_contact.global_position = contact
	_tint(_contact, verdict)
	_contact.visible = true

	# Priced from what the player is carrying RIGHT NOW, by the move's own
	# function rather than a copy of it -- a marker that drifts from the
	# behaviour it illustrates is worse than no marker.
	var height: float = WallClimbMove.climb_height( \
		player.horizontal_speed(), player.velocity.y, cfg)
	if height <= 0.01 or not tall_enough or not square_enough:
		_reach.visible = false
		return
	_reach.mesh.size = Vector3(SPAR_THICKNESS, height, SPAR_THICKNESS)
	_reach.global_position = contact + Vector3.UP * (height * 0.5)
	_reach.rotation = Vector3.ZERO
	_tint(_reach, verdict)
	_reach.visible = true
