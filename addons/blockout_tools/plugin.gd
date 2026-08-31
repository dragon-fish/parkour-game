@tool
extends EditorPlugin

# Drag a rectangle across a surface; a CSGBox3D is laid flush against it, one
# grid step thick. Pulling it to height is Godot's own CSG size handle -- this
# plugin deliberately stops at the rectangle.
#
# WHY SO LITTLE UI: Cyclops Level Builder does the same job with its own menu
# system, several docks and an autoload, and on macOS that combination locks
# the editor's input up entirely (upstream issue #242, open, unreproducible for
# its Windows-only author). One toggle and one field is the whole surface here,
# and input arrives through _forward_3d_gui_input -- the hook scoped to the 3D
# viewport -- never a global _input().

const Geometry := preload("res://addons/blockout_tools/block_geometry.gd")
const Probe := preload("res://addons/blockout_tools/surface_probe.gd")

## Far enough to cross any level from any angle. A ray is cheap; a click that
## silently falls short is not.
const RAY_LENGTH: float = 4096.0

const FILL_COLOUR := Color(0.35, 0.7, 1.0, 0.18)
const EDGE_COLOUR := Color(0.55, 0.85, 1.0, 0.9)

## The toolbar icon: an isometric box with its top face filled, for "a
## rectangle drawn on a face".
##
## Drawn in WHITE and tinted through the button's icon_* theme colours, which
## is what lets it read as inactive, hovered and armed without three files --
## and what keeps it visible under a light editor theme. A coloured icon here
## would be invisible in one theme or the other.
##
## Built with Image.load_svg_from_string() rather than shipped as a .svg: an
## imported texture needs a .import file and a first import pass, and it would
## be rasterised once at whatever editor scale did the importing.
const ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
<g fill="none" stroke="#ffffff" stroke-width="1.3" stroke-linejoin="round">
<path d="M8 1.7 14.1 5.3 8 8.9 1.9 5.3Z" fill="#ffffff"/>
<path d="M1.9 5.3v5.5L8 14.3l6.1-3.5V5.3"/>
<path d="M8 8.9v5.4"/>
</g></svg>"""

var _bar: HBoxContainer = null
var _toggle: Button = null
var _step_field: SpinBox = null

var _dragging: bool = false
var _anchor: Vector3 = Vector3.ZERO
var _face: Basis = Basis.IDENTITY
var _extent: Vector2 = Vector2.ZERO

func _enter_tree() -> void:
	_toggle = _build_toggle()
	_toggle.toggled.connect(_on_toggled)

	_step_field = SpinBox.new()
	_step_field.min_value = 0.0
	_step_field.max_value = 8.0
	_step_field.step = 0.05
	_step_field.value = 0.5
	_step_field.prefix = "grid "
	_step_field.custom_minimum_size = Vector2(96, 0)
	_step_field.tooltip_text = "Grid the drag snaps to, and the thickness a new block starts at. 0 disables snapping."

	_bar = HBoxContainer.new()
	_bar.add_child(VSeparator.new())
	_bar.add_child(_toggle)
	_bar.add_child(_step_field)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)

## Dressed as one of the 3D toolbar's own mode buttons -- flat, icon only, an
## accent-tinted background while armed. It cannot actually JOIN that group:
## the editor exposes no API for adding to it, so picking Move or Rotate will
## not switch this off.
func _build_toggle() -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.flat = true
	button.tooltip_text = "Block: drag a rectangle on any surface to lay a CSGBox3D against it.\n" \
		+ "Hold any modifier to box select instead. Esc or right click cancels a drag."

	var image := Image.new()
	if image.load_svg_from_string(ICON_SVG, EditorInterface.get_editor_scale()) == OK:
		button.icon = ImageTexture.create_from_image(image)
	else:
		button.text = "Block"

	var theme: Theme = EditorInterface.get_editor_theme()
	if theme == null:
		return button
	var accent := Color(0.4, 0.7, 1.0)
	if theme.has_color(&"accent_color", &"Editor"):
		accent = theme.get_color(&"accent_color", &"Editor")
	var resting := Color(1, 1, 1)
	if theme.has_color(&"font_color", &"Editor"):
		resting = theme.get_color(&"font_color", &"Editor")

	button.add_theme_color_override(&"icon_normal_color", Color(resting, 0.7))
	button.add_theme_color_override(&"icon_hover_color", resting)
	button.add_theme_color_override(&"icon_pressed_color", accent)
	button.add_theme_color_override(&"icon_hover_pressed_color", accent)

	# An explicit armed background rather than trusting the flat button's own
	# pressed stylebox: whether a flat Button paints one is a theme's decision,
	# and "am I armed?" is the one thing about this tool that must never be
	# ambiguous -- a bare left drag means something different either way.
	var armed := StyleBoxFlat.new()
	armed.bg_color = Color(accent, 0.22)
	armed.set_corner_radius_all(4)
	armed.set_content_margin_all(4)
	button.add_theme_stylebox_override(&"pressed", armed)
	button.add_theme_stylebox_override(&"hover_pressed", armed)
	return button

func _exit_tree() -> void:
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.queue_free()
	_bar = null
	_toggle = null
	_step_field = null

# The editor only forwards viewport input to a plugin that claims the current
# selection, so this claims everything -- and _on_toggled makes sure something
# is selected at all. Without both, arming the tool with an empty selection
# yields a tool that silently receives nothing.
func _handles(_object: Object) -> bool:
	return true

func _on_toggled(pressed: bool) -> void:
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

func _step() -> float:
	return _step_field.value if _step_field != null else 0.0

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _toggle == null or not _toggle.button_pressed or camera == null:
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
	# Snap in world space so blocks line up with the grid and with each other,
	# then put the result back on the surface -- snapping alone would lift the
	# anchor off anything that is not axis-aligned.
	_anchor = Plane(normal, point).project(Geometry.snap_vector(point, _step()))
	_extent = Vector2.ZERO
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
	var step: float = _step()
	_extent = Vector2(Geometry.snap(local.x, step), Geometry.snap(local.z, step))
	update_overlays()

func _cancel() -> void:
	_dragging = false
	_extent = Vector2.ZERO
	update_overlays()

func _commit() -> int:
	_dragging = false
	update_overlays()
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return AFTER_GUI_INPUT_STOP

	var step: float = _step()
	var plan: Dictionary = Geometry.block_from_drag(_anchor, _face, _extent, step, step)
	var box := CSGBox3D.new()
	box.name = "Block"
	box.size = plan["size"]
	box.transform = root.global_transform.affine_inverse() * (plan["transform"] as Transform3D)
	box.use_collision = true

	# Always the scene root, never the current selection: _commit selects what
	# it just made so the CSG size handles are under the mouse straight away,
	# and parenting to the selection would then thread every new block through
	# the previous one.
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Draw block")
	undo.add_do_method(root, "add_child", box, true)
	undo.add_do_method(box, "set_owner", root)
	undo.add_do_reference(box)
	undo.add_undo_method(root, "remove_child", box)
	undo.commit_action()

	var selection: EditorSelection = EditorInterface.get_selection()
	selection.clear()
	selection.add_node(box)
	return AFTER_GUI_INPUT_STOP

func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _dragging:
		return
	var camera: Camera3D = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	if camera == null:
		return
	var corners: Array[Vector3] = [
		_anchor,
		_anchor + _face * Vector3(_extent.x, 0.0, 0.0),
		_anchor + _face * Vector3(_extent.x, 0.0, _extent.y),
		_anchor + _face * Vector3(0.0, 0.0, _extent.y),
	]
	var screen := PackedVector2Array()
	for corner in corners:
		if camera.is_position_behind(corner):
			return
		screen.append(camera.unproject_position(corner))
	overlay.draw_colored_polygon(screen, FILL_COLOUR)
	screen.append(screen[0])
	overlay.draw_polyline(screen, EDGE_COLOUR, 2.0)
