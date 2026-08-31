@tool
extends EditorPlugin

# Drag on a surface; a CSG solid is laid flush against it, thin. Pulling it to
# height is Godot's own CSG handle -- this plugin deliberately stops at the
# footprint. A box is drawn corner to corner, a cylinder and a sphere centre to
# rim.
#
# WHY SO LITTLE UI: Cyclops Level Builder does the same job with its own menu
# system, several docks and an autoload, and on macOS that combination locks
# the editor's input up entirely (upstream issue #242, open, unreproducible for
# its Windows-only author). A few toolbar controls is the whole surface here,
# and input arrives through _forward_3d_gui_input -- the hook scoped to the 3D
# viewport -- never a global _input().

const Geometry := preload("res://addons/blockout_tools/block_geometry.gd")
const Probe := preload("res://addons/blockout_tools/surface_probe.gd")

enum Shape { BOX, CYLINDER, SPHERE }

## Far enough to cross any level from any angle. A ray is cheap; a click that
## silently falls short is not.
const RAY_LENGTH: float = 4096.0

const FILL_COLOUR := Color(0.35, 0.7, 1.0, 0.18)
const EDGE_COLOUR := Color(0.55, 0.85, 1.0, 0.9)
const CIRCLE_SEGMENTS: int = 48

## Where the toolbar's two fields are remembered. Editor project metadata lands
## in .godot/, which is per-machine and already ignored by git -- a grid size
## is one person's working habit, not the project's.
const PREFS_SECTION := "blockout_tools"

## 0.2 in both because that is the unit this project's heights are built from
## -- 3.8, 4.4, 5.0 -- so a new solid and the first pull off it both land on
## one. They are starting points; the fields override them and remember.
const DEFAULT_GRID: float = 0.2
const DEFAULT_THICKNESS: float = 0.2

const SHAPE_BUTTONS: Array[Dictionary] = [
	{"shape": Shape.BOX, "icon": "CSGBox3D", "label": "Box",
		"hint": "Box: drag corner to corner."},
	{"shape": Shape.CYLINDER, "icon": "CSGCylinder3D", "label": "Cyl",
		"hint": "Cylinder: drag centre to rim."},
	{"shape": Shape.SPHERE, "icon": "CSGSphere3D", "label": "Ball",
		"hint": "Sphere: drag centre to rim. Rests on the surface."},
]

var _bar: HBoxContainer = null
var _buttons: Array[Button] = []
var _group: ButtonGroup = null
var _grid_field: SpinBox = null
var _thickness_field: SpinBox = null

var _dragging: bool = false
var _anchor: Vector3 = Vector3.ZERO
var _face: Basis = Basis.IDENTITY
var _extent: Vector2 = Vector2.ZERO
var _radius: float = 0.0

func _enter_tree() -> void:
	_bar = HBoxContainer.new()
	_bar.add_child(VSeparator.new())

	_group = ButtonGroup.new()
	# So clicking the armed shape disarms it, instead of leaving no way back to
	# a viewport that behaves normally.
	_group.allow_unpress = true
	for entry in SHAPE_BUTTONS:
		var button: Button = _build_shape_button(entry)
		_buttons.append(button)
		_bar.add_child(button)

	_grid_field = _build_field("grid ", DEFAULT_GRID, 0.0,
		"Grid the drag snaps to, in metres. 0 disables snapping.\n"
		+ "Type any value; the arrows step by 0.2.")
	_thickness_field = _build_field("thick ", DEFAULT_THICKNESS, 0.01,
		"How thick a new solid starts out. Godot's own CSG handle takes it from there.")
	_bar.add_child(_grid_field)
	_bar.add_child(_thickness_field)
	_load_prefs()

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)

func _exit_tree() -> void:
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.queue_free()
	_bar = null
	_buttons.clear()
	_group = null
	_grid_field = null
	_thickness_field = null

## Dressed as one of the 3D toolbar's own mode buttons -- flat, icon only, an
## accent plate while armed. It cannot actually JOIN that group: the editor
## exposes no API for adding to it, so picking Move or Rotate will not switch
## this off.
func _build_shape_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.flat = true
	button.button_group = _group
	button.tooltip_text = "%s\nHold any modifier to box select instead. Esc or right click cancels." \
		% entry["hint"]

	var theme: Theme = EditorInterface.get_editor_theme()
	if theme == null:
		button.text = entry["label"]
		return button
	var icon_name: StringName = StringName(entry["icon"])
	if theme.has_icon(icon_name, &"EditorIcons"):
		button.icon = theme.get_icon(icon_name, &"EditorIcons")
	else:
		button.text = entry["label"]

	var accent := Color(0.4, 0.7, 1.0)
	if theme.has_color(&"accent_color", &"Editor"):
		accent = theme.get_color(&"accent_color", &"Editor")

	# Fade, do not tint: these icons carry their own colours and an accent
	# multiply turns them to mud. The gap has to be WIDE -- armed changes what
	# a bare left drag means, and a few percent of alpha is not a state anyone
	# reads at a glance. Do not narrow it back, and do not leave these unset:
	# the default theme fades the PRESSED state, which reads as armed-is-off.
	button.add_theme_color_override(&"icon_normal_color", Color(1, 1, 1, 0.35))
	button.add_theme_color_override(&"icon_hover_color", Color(1, 1, 1, 0.7))
	button.add_theme_color_override(&"icon_pressed_color", Color(1, 1, 1, 1))
	button.add_theme_color_override(&"icon_hover_pressed_color", Color(1, 1, 1, 1))

	var armed := StyleBoxFlat.new()
	armed.bg_color = Color(accent, 0.35)
	armed.border_color = accent
	armed.set_border_width_all(1)
	armed.set_corner_radius_all(4)
	armed.set_content_margin_all(4)
	button.add_theme_stylebox_override(&"pressed", armed)
	button.add_theme_stylebox_override(&"hover_pressed", armed)
	button.toggled.connect(_on_shape_toggled)
	return button

func _build_field(prefix: String, value: float, minimum: float, hint: String) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = 8.0
	# A SpinBox rounds its value to `step`, so `step` is the finest grid that
	# can be TYPED here, not just the arrows' stride -- that is what
	# custom_arrow_step is for. Keep them apart: a 0.05 step made 0.01 round
	# away to nothing.
	field.step = 0.01
	field.custom_arrow_step = 0.2
	field.value = value
	field.prefix = prefix
	field.custom_minimum_size = Vector2(88, 0)
	field.tooltip_text = hint
	field.value_changed.connect(_on_field_changed)
	return field

func _prefs() -> EditorSettings:
	return EditorInterface.get_editor_settings()

func _load_prefs() -> void:
	var settings: EditorSettings = _prefs()
	if settings == null:
		return
	_grid_field.value = float(settings.get_project_metadata(
		PREFS_SECTION, "grid", DEFAULT_GRID))
	_thickness_field.value = float(settings.get_project_metadata(
		PREFS_SECTION, "thickness", DEFAULT_THICKNESS))

func _on_field_changed(_value: float) -> void:
	var settings: EditorSettings = _prefs()
	if settings == null:
		return
	settings.set_project_metadata(PREFS_SECTION, "grid", _grid_field.value)
	settings.set_project_metadata(PREFS_SECTION, "thickness", _thickness_field.value)

# The editor only forwards viewport input to a plugin that claims the current
# selection, so this claims everything -- and _on_shape_toggled makes sure
# something is selected at all. Without both, arming a shape with an empty
# selection yields a tool that silently receives nothing.
func _handles(_object: Object) -> bool:
	return true

func _on_shape_toggled(pressed: bool) -> void:
	_dragging = false
	update_overlays()
	if not pressed:
		return
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var selection: EditorSelection = EditorInterface.get_selection()
	if selection.get_selected_nodes().is_empty():
		selection.add_node(root)

func _armed_shape() -> int:
	for i in _buttons.size():
		if _buttons[i].button_pressed:
			return SHAPE_BUTTONS[i]["shape"]
	return -1

func _disarm() -> void:
	for button in _buttons:
		button.set_pressed_no_signal(false)

func _grid() -> float:
	return _grid_field.value if _grid_field != null else 0.0

func _thickness() -> float:
	return _thickness_field.value if _thickness_field != null else DEFAULT_THICKNESS

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if camera == null or _armed_shape() < 0:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				# A modifier means the editor's gesture, not ours. Box select
				# and its add/subtract variants stay reachable without leaving
				# the tool, which is the whole reason this check exists -- and
				# claiming a modifier of our own is not an option: Alt+Drag is
				# already "move selected node" and Ctrl/Cmd+Alt+Drag is scale.
				if button.shift_pressed or button.ctrl_pressed \
						or button.meta_pressed or button.alt_pressed:
					return AFTER_GUI_INPUT_PASS
				return _begin(camera, button.position)
			if _dragging:
				return _commit()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and _dragging:
			_cancel()
			return AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and _dragging:
		_track(camera, (event as InputEventMouseMotion).position)
		return AFTER_GUI_INPUT_STOP
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and _dragging:
			_cancel()
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _begin(camera: Camera3D, screen: Vector2) -> int:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return AFTER_GUI_INPUT_PASS
	var from: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var hit: Dictionary = Probe.raycast(camera, from, from + direction * RAY_LENGTH, root)

	var point: Vector3
	var normal: Vector3
	if hit.is_empty():
		# Nothing under the cursor is still a place to build: fall back to the
		# ground plane so an empty scene is not a dead viewport.
		var ground := Plane(Vector3.UP, 0.0)
		var landing: Variant = ground.intersects_ray(from, direction)
		if landing == null:
			return AFTER_GUI_INPUT_PASS
		point = landing
		normal = Vector3.UP
	else:
		point = hit["position"]
		normal = hit["normal"]

	_face = Geometry.face_basis(normal)
	# Snap in world space so solids line up with the grid and with each other,
	# then put the result back on the surface -- snapping alone would lift the
	# anchor off anything that is not axis-aligned.
	_anchor = Plane(normal, point).project(Geometry.snap_vector(point, _grid()))
	_extent = Vector2.ZERO
	_radius = 0.0
	_dragging = true
	update_overlays()
	return AFTER_GUI_INPUT_STOP

func _track(camera: Camera3D, screen: Vector2) -> void:
	var from: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var surface := Plane(_face.y, _anchor)
	var landing: Variant = surface.intersects_ray(from, direction)
	if landing == null:
		return
	var local: Vector3 = _face.transposed() * ((landing as Vector3) - _anchor)
	var grid: float = _grid()
	_extent = Vector2(Geometry.snap(local.x, grid), Geometry.snap(local.z, grid))
	_radius = Geometry.snap(Vector2(local.x, local.z).length(), grid)
	update_overlays()

func _cancel() -> void:
	_dragging = false
	_extent = Vector2.ZERO
	_radius = 0.0
	update_overlays()

func _commit() -> int:
	var shape: int = _armed_shape()
	_dragging = false
	update_overlays()
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null or shape < 0:
		return AFTER_GUI_INPUT_STOP

	var grid: float = _grid()
	var thickness: float = _thickness()
	var solid: CSGShape3D
	var placement: Transform3D
	match shape:
		Shape.CYLINDER:
			var plan: Dictionary = Geometry.cylinder_from_drag(
				_anchor, _face, _radius, thickness, grid)
			var cylinder := CSGCylinder3D.new()
			cylinder.radius = plan["radius"]
			cylinder.height = plan["height"]
			solid = cylinder
			placement = plan["transform"]
		Shape.SPHERE:
			var plan: Dictionary = Geometry.sphere_from_drag(
				_anchor, _face, _radius, grid)
			var sphere := CSGSphere3D.new()
			sphere.radius = plan["radius"]
			solid = sphere
			placement = plan["transform"]
		_:
			var plan: Dictionary = Geometry.block_from_drag(
				_anchor, _face, _extent, thickness, grid)
			var box := CSGBox3D.new()
			box.size = plan["size"]
			solid = box
			placement = plan["transform"]

	solid.name = "Block"
	solid.transform = root.global_transform.affine_inverse() * placement
	solid.use_collision = true

	# Always the scene root, never the current selection: the new solid is
	# selected below so its CSG handles are under the mouse straight away, and
	# parenting to the selection would then thread every new one through the
	# last.
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Draw solid")
	undo.add_do_method(root, "add_child", solid, true)
	undo.add_do_method(solid, "set_owner", root)
	undo.add_do_reference(solid)
	undo.add_undo_method(root, "remove_child", solid)
	undo.commit_action()

	var selection: EditorSelection = EditorInterface.get_selection()
	selection.clear()
	selection.add_node(solid)
	# Disarm, because the next thing anyone does is pull the thing they just
	# drew to height -- and while a shape is armed this plugin eats the bare
	# left click, so the CSG handles cannot be grabbed. Selecting the new solid
	# without disarming hands over a gizmo that does not answer.
	_disarm()
	return AFTER_GUI_INPUT_STOP

func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _dragging:
		return
	var camera: Camera3D = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	if camera == null:
		return
	var corners: Array[Vector3] = _footprint()
	var screen := PackedVector2Array()
	for corner in corners:
		if camera.is_position_behind(corner):
			return
		screen.append(camera.unproject_position(corner))
	if screen.size() < 3:
		return
	overlay.draw_colored_polygon(screen, FILL_COLOUR)
	screen.append(screen[0])
	overlay.draw_polyline(screen, EDGE_COLOUR, 2.0)

func _footprint() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _armed_shape() == Shape.BOX:
		points.append(_anchor)
		points.append(_anchor + _face * Vector3(_extent.x, 0.0, 0.0))
		points.append(_anchor + _face * Vector3(_extent.x, 0.0, _extent.y))
		points.append(_anchor + _face * Vector3(0.0, 0.0, _extent.y))
		return points
	var reach: float = maxf(_radius, 0.001)
	for i in CIRCLE_SEGMENTS:
		var angle: float = TAU * float(i) / float(CIRCLE_SEGMENTS)
		points.append(_anchor + _face * Vector3(cos(angle) * reach, 0.0, sin(angle) * reach))
	return points
