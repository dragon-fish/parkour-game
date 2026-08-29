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
#   SPAR rising from the contact point to WHERE A KICK WOULD END
#       A fixed length, because a climb travels a fixed distance -- what a
#       run-up buys is arriving sooner, not arriving higher. Drawn anyway, and
#       drawn from the contact point rather than from the feet, because that is
#       the question worth answering before committing: does the top of this
#       spar clear the lip I am trying to reach?
#
# Queried every frame regardless of state, not only while climbing -- seeing
# what the probe thinks about a wall BEFORE jumping at it is most of the value.

## Assigned by Arena. Optional so nothing breaks without one.
@export var player: Player

## DEBUG-ONLY SIZES.
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
	# The group is the whole registration: the tuning panel finds every overlay
	# through it and duck-types show_overlay()/overlay_shown().
	add_to_group("debug_overlay")

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

## The name the overlay protocol uses, kept separate from _hide_all() only so
## a null _contact before _ready() cannot crash a toggle.
func _hide_markers() -> void:
	if _contact == null:
		return
	_hide_all()

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


func _process(_delta: float) -> void:
	if not _shown or player == null or player.probes == null or _contact == null:
		return
	# The same direction the entry test measures against, so the marker cannot
	# disagree with the decision it is illustrating. ZERO means standing still
	# asking for nothing, which is a refusal rather than an angle.
	var heading: Vector3 = player.approach_direction()
	if heading == Vector3.ZERO:
		_hide_all()
		return

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
	var contact: Vector3 = player.global_position + heading * float(hit["distance"])
	contact.y = player.global_position.y + Probes.WALL_AHEAD_CHEST_Y
	_contact.global_position = contact
	_tint(_contact, verdict)
	_contact.visible = true

	var height: float = cfg.climb_height
	if height <= 0.01 or not tall_enough or not square_enough:
		_reach.visible = false
		return
	_reach.mesh.size = Vector3(SPAR_THICKNESS, height, SPAR_THICKNESS)
	_reach.global_position = contact + Vector3.UP * (height * 0.5)
	_reach.rotation = Vector3.ZERO
	_tint(_reach, verdict)
	_reach.visible = true
