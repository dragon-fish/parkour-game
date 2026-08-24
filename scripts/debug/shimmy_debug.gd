class_name ShimmyDebug
extends Node3D

# Draws the shimmy's probes where they were actually fired. Toggled from the
# F1 tuning panel's Debug page -- it used to be its own key (F11), but that
# collided with player.gd's own use of F11 for mouse recapture, so the key was
# retired here and the panel's checkbox is now the only way to show this.
#
# ✅ THE OWNER, on a corner in me_level0 that refuses and that neither of us can
# reproduce in a whitebox: "你把可以左右爬的路径画出来."
#
# ⚠️ AND THE OTHER HALF OF THAT REQUEST IS DELIBERATELY NOT DONE. The proposal
# was to cache a climbable path from the topology at grab time and stop
# raycasting the attached model -- but the owner had already built the same
# topology out of two boxes in a whitebox and rounded the corner easily, which
# is evidence that the topology is not the difference. Rewriting the mechanism
# to be topology-driven would be rebuilding around a cause that has been ruled
# out, and a path extractor for arbitrary collision shapes is a large thing to
# build on a hunch. It stays on the table; it is not what this is.
#
# What IS the difference is unknown, and that is the actual problem: four
# refusals look identical from outside, and the HUD line added with them names
# the branch without showing where it looked. This shows where.
#
# READS RECORDED SEGMENTS, never re-derives them. GrabMove keeps the segments
# Probes actually fired; drawing a second copy of the same arithmetic would
# agree with the first right up until a difference is the thing being looked
# for. Same rule IntoGrabMove.hanging_pose() follows.

@export var player: Player

## Anything that missed. One colour for every failure, because the question
## being asked is "which one is red".
@export var miss_colour := Color(1.0, 0.25, 0.25)
@export var ledge_colour := Color(0.3, 0.9, 1.0)
@export var face_colour := Color(1.0, 0.85, 0.2)
@export var corner_colour := Color(0.9, 0.4, 1.0)
@export var body_colour := Color(0.85, 0.85, 0.85)
## The anchor the hands are on, and the way travel would carry them.
@export var anchor_colour := Color(0.2, 1.0, 0.4)
@export var path_length: float = 2.0

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _lines: StandardMaterial3D
var _shown := false

const COLOURS := {
	"ledge": "ledge_colour",
	"face": "face_colour",
	"corner look": "corner_colour",
	"corner top": "corner_colour",
	"body": "body_colour",
}

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	# Everything below is described in WORLD space every frame, so the instance
	# must not add a transform of its own. Same arrangement CapsuleDebug uses.
	_instance.top_level = true
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines = StandardMaterial3D.new()
	_lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines.vertex_color_use_as_albedo = true
	# Through walls: a probe that fails INSIDE geometry is exactly the case
	# worth seeing, and it is the one a depth test would hide.
	_lines.no_depth_test = true
	_lines.render_priority = 3
	add_child(_instance)
	_instance.visible = false
	# So the tuning panel's Debug page can find this overlay by name and
	# duck-type show_overlay()/overlay_shown() on it, without either side
	# knowing about the other's class.
	add_to_group("debug_overlay")

## Turns the probes on or off from code. Mirrors CapsuleDebug.show_overlay()
## and ScriptedPathDebug.show_overlay() -- see the header comment for why this
## overlay has no keyboard toggle of its own any more.
func show_overlay(on: bool) -> void:
	_shown = on
	if _instance != null:
		_instance.visible = on

## Duck-typed getter the tuning panel's Debug page reads every frame to keep
## its checkbox in sync, matching the other three overlays' interface.
func overlay_shown() -> bool:
	return _shown

func _process(_delta: float) -> void:
	if not _shown or player == null or player.move_manager == null:
		return
	_mesh.clear_surfaces()
	if player.move_manager.current_name != Move.GRAB:
		return
	var grab = player.move_manager.move_for(Move.GRAB)
	if grab == null or not grab.has_method("probe_trace"):
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lines)
	# THE LEDGE THE HANDS ARE ON, first, because everything else is measured
	# from it: a cross at the anchor and the line travel would follow.
	if grab.has_method("anchor_debug"):
		var anchor: Dictionary = grab.anchor_debug()
		_mesh.surface_set_color(anchor_colour)
		_cross(anchor["edge"], 0.18)
		var along: Vector3 = anchor["along"]
		if along.length_squared() > 0.0001:
			_line(anchor["edge"] - along * path_length,
					anchor["edge"] + along * path_length)
		# The face's own normal, so a shimmy running the wrong way along the
		# wrong wall is visible as such rather than as a probe that missed.
		var outward: Vector3 = anchor["outward"]
		if outward.length_squared() > 0.0001:
			_line(anchor["edge"], anchor["edge"] + outward * 0.5)

	for entry in grab.probe_trace():
		var hit: bool = bool(entry.get("hit", false))
		var key: String = String(entry.get("label", ""))
		var colour: Color = miss_colour
		if hit and COLOURS.has(key):
			colour = get(COLOURS[key])
		_mesh.surface_set_color(colour)
		_line(entry["from"], entry["to"])
		# A tick at the far end, so a very short probe is still findable and so
		# the DIRECTION it was fired in is readable.
		_cross(entry["to"], 0.06)
	_mesh.surface_end()

func _line(a: Vector3, b: Vector3) -> void:
	_mesh.surface_add_vertex(a)
	_mesh.surface_add_vertex(b)

func _cross(at: Vector3, size: float) -> void:
	_line(at - Vector3.RIGHT * size, at + Vector3.RIGHT * size)
	_line(at - Vector3.UP * size, at + Vector3.UP * size)
	_line(at - Vector3.BACK * size, at + Vector3.BACK * size)
