class_name ScriptedPathDebug
extends Node3D

# Draws the path a scripted move is following, and the path the body actually
# took. F12.
#
# ✅ THE OWNER: "你能不能把曲线画出来啊，我真的不知道现在的曲线长什么样子." Four
# rounds of describing a curve in prose had produced four different pictures in
# our two heads -- the capsule wireframe settled the vault-height argument the
# same way, and for the same reason.
#
# ⚠️ IT ASKS THE MOVE TO SAMPLE ITSELF rather than recomputing the arithmetic.
# A drawer with its own copy is a picture of a SECOND implementation, agreeing
# with the first right up until a difference is what you are looking for. Same
# rule Probes follows by handing its segments back with its answers.
#
# THE TRAIL IS THE OTHER HALF. The planned curve says where the move intends to
# go; the trail says where the body got to. They come apart whenever something
# else is also writing the position -- a collision, a clip offset, a fold -- and
# that gap is invisible from inside either one.

@export var player: Player

@export_group("Colours")
## The plan: what sample() says, end to end.
@export var plan_colour := Color(0.35, 0.95, 0.55)
## Where the body has actually been since the move began.
@export var trail_colour := Color(1.0, 0.75, 0.2)
## The two knees, where the rise hands over to the crossing and the crossing to
## the drop. The whole shape argument is about where these sit.
@export var knee_colour := Color(1.0, 0.4, 0.9)
## Start and finish.
@export var end_colour := Color(0.4, 0.8, 1.0)
## How far along the plan the move currently is.
@export var head_colour := Color(1.0, 1.0, 1.0)

@export_group("Detail")
@export var samples: int = 48
@export var marker_size: float = 0.12

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _lines: StandardMaterial3D
var _shown := false
var _trail: PackedVector3Array = PackedVector3Array()
var _tracking := false

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	# Described in WORLD space every frame, so the instance must add no
	# transform of its own. Same arrangement CapsuleDebug and ShimmyDebug use.
	_instance.top_level = true
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines = StandardMaterial3D.new()
	_lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines.vertex_color_use_as_albedo = true
	# Through walls, because the whole subject is a path that goes through one.
	_lines.no_depth_test = true
	_lines.render_priority = 4
	add_child(_instance)
	_instance.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F12:
		_shown = not _shown
		_instance.visible = _shown

func _process(_delta: float) -> void:
	if player == null or player.move_manager == null:
		return
	var move = player.move_manager.move_for(player.move_manager.current_name)
	var path: Dictionary = {}
	if move != null and move.has_method("path_debug"):
		path = move.path_debug()

	# THE TRAIL IS COLLECTED WHETHER OR NOT THE VIEW IS ON, so switching it on
	# mid-vault shows the vault rather than the tail of it.
	if path.is_empty():
		_tracking = false
	else:
		if not _tracking:
			_trail.clear()
			_tracking = true
		if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(player.global_position) > 0.01:
			_trail.push_back(player.global_position)

	if not _shown:
		return
	_mesh.clear_surfaces()
	if path.is_empty() and _trail.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lines)
	if not path.is_empty():
		_draw_plan(move, path)
	_draw_trail()
	_mesh.surface_end()

func _draw_plan(move, path: Dictionary) -> void:
	# THE MOVE SAMPLES ITSELF. See the header.
	_mesh.surface_set_color(plan_colour)
	var previous: Vector3 = move.sample(0.0)
	for i in range(1, samples + 1):
		var t: float = float(i) / float(samples)
		var at: Vector3 = move.sample(t)
		_line(previous, at)
		previous = at

	# The knees, which is where the argument about this shape actually lives:
	# how much of the journey is spent rising before any of it goes forward.
	_mesh.surface_set_color(knee_colour)
	for key in ["knee_rise", "knee_fall"]:
		var t: float = float(path.get(key, -1.0))
		if t >= 0.0:
			_cross(move.sample(t), marker_size)

	_mesh.surface_set_color(end_colour)
	_cross(path["from"], marker_size * 1.4)
	_cross(path["to"], marker_size * 1.4)
	# A plumb line at each end, so the RISE is readable against the ground
	# rather than having to be judged by eye against a curve.
	_line(path["from"], Vector3(path["from"].x, path["peak"], path["from"].z))
	_line(path["to"], Vector3(path["to"].x, path["peak"], path["to"].z))

	_mesh.surface_set_color(head_colour)
	_cross(move.sample(float(path.get("progress", 0.0))), marker_size)

func _draw_trail() -> void:
	if _trail.size() < 2:
		return
	_mesh.surface_set_color(trail_colour)
	for i in range(1, _trail.size()):
		_line(_trail[i - 1], _trail[i])

func _line(a: Vector3, b: Vector3) -> void:
	_mesh.surface_add_vertex(a)
	_mesh.surface_add_vertex(b)

func _cross(at: Vector3, size: float) -> void:
	_line(at - Vector3.RIGHT * size, at + Vector3.RIGHT * size)
	_line(at - Vector3.UP * size, at + Vector3.UP * size)
	_line(at - Vector3.BACK * size, at + Vector3.BACK * size)
