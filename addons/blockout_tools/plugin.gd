@tool
extends EditorPlugin

# Drag on a surface; a CSG solid is laid flush against it, thin. Pulling it to
# height is Godot's own CSG handle -- this plugin deliberately stops at the
# footprint. A box is drawn corner to corner; a cylinder and a sphere centre to
# rim, the sphere centred on the point the drag started from.
#
# ONE CHECKBOX AND ONE PICKER, not a button per shape: the toolbar is shared
# with the editor's own controls and a row that grows with every shape added
# would crowd them out. The picker carries the shape and its icon, which leaves
# the checkbox saying only on or off -- the one thing it has to say without
# ambiguity, since armed changes what a bare left drag means.
#
# WHY SO LITTLE UI generally: Cyclops Level Builder does the same job with its
# own menu system, several docks and an autoload, and on macOS that combination
# locks the editor's input up entirely (upstream issue #242, open,
# unreproducible for its Windows-only author). Input here arrives through
# _forward_3d_gui_input -- the hook scoped to the 3D viewport -- never a global
# _input().

const Geometry := preload("res://addons/blockout_tools/block_geometry.gd")
const Probe := preload("res://addons/blockout_tools/surface_probe.gd")

enum Shape { BOX, CYLINDER, SPHERE }

## What a drag produces. The shape picker says which solid; this says whether
## it is geometry or a volume.
enum Output { CSG, COLLISION }

const OUTPUTS: Array[Dictionary] = [
	{"output": Output.CSG, "label": "CSG",
		"hint": "A CSGShape3D: whitebox geometry with collision baked in."},
	{"output": Output.COLLISION, "label": "Collision",
		"hint": "A CollisionShape3D. Dropped into the selected body or area if there is one,"
			+ " otherwise wrapped in a new Area3D so it is a working trigger."},
]

## Far enough to cross any level from any angle. A ray is cheap; a click that
## silently falls short is not.
const RAY_LENGTH: float = 4096.0

const FILL_COLOUR := Color(0.35, 0.7, 1.0, 0.18)
const EDGE_COLOUR := Color(0.55, 0.85, 1.0, 0.9)
const CIRCLE_SEGMENTS: int = 48

## Where the toolbar's settings are remembered. Editor project metadata lands
## in .godot/, which is per-machine and already ignored by git -- a grid size is
## one person's working habit, not the project's.
const PREFS_SECTION := "blockout_tools"

## 0.2 in both because that is the unit this project's heights are built from
## -- 3.8, 4.4, 5.0 -- so a new solid and the first pull off it both land on
## one. They are starting points; the fields override them and remember.
const DEFAULT_GRID: float = 0.2
const DEFAULT_THICKNESS: float = 0.2

const SHAPES: Array[Dictionary] = [
	{"shape": Shape.BOX, "icon": "CSGBox3D", "label": "Box",
		"hint": "Box: drag corner to corner."},
	{"shape": Shape.CYLINDER, "icon": "CSGCylinder3D", "label": "Cylinder",
		"hint": "Cylinder: drag centre to rim."},
	{"shape": Shape.SPHERE, "icon": "CSGSphere3D", "label": "Sphere",
		"hint": "Sphere: drag centre to rim. Centred on where the drag started."},
]

var _bar: HBoxContainer = null
var _toggle: CheckBox = null
var _picker: OptionButton = null
var _output_picker: OptionButton = null
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

	_toggle = _build_toggle()
	_picker = _build_picker()
	_output_picker = _build_output_picker()
	_grid_field = _build_field("grid ", DEFAULT_GRID, 0.0,
		"Grid the drag snaps to, in metres. 0 disables snapping.\n"
		+ "Type any value; the arrows step by 0.2.")
	_thickness_field = _build_field("thick ", DEFAULT_THICKNESS, 0.01,
		"How thick a new solid starts out. Godot's own CSG handle takes it from there.")
	_bar.add_child(_toggle)
	_bar.add_child(_picker)
	_bar.add_child(_output_picker)
	_bar.add_child(_grid_field)
	_bar.add_child(_thickness_field)

	_load_prefs()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)

func _exit_tree() -> void:
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.queue_free()
	_bar = null
	_toggle = null
	_picker = null
	_output_picker = null
	_grid_field = null
	_thickness_field = null

## A plain CheckBox, because the picker beside it already carries the shape's
## icon -- the switch only has to say on or off, and a checkbox says that in
## the editor's own vocabulary without a stylebox fighting the theme for
## contrast.
##
## Being unmistakable matters here more than it looks: armed changes what a
## bare left drag means in the viewport. An earlier icon-button version leaned
## on alpha for the same job and read as off when it was on.
func _build_toggle() -> CheckBox:
	var box := CheckBox.new()
	box.tooltip_text = "Draw the picked solid on any surface.\n" \
		+ "Hold any modifier to box select instead. Esc or right click cancels."
	box.toggled.connect(_on_toggled)
	return box

func _build_picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.flat = true
	# Otherwise the control keeps the width of "Cylinder" whatever is picked,
	# and this row is a guest on the editor's own toolbar.
	picker.fit_to_longest_item = false
	var theme: Theme = EditorInterface.get_editor_theme()
	for entry in SHAPES:
		var icon_name := StringName(entry["icon"])
		if theme != null and theme.has_icon(icon_name, &"EditorIcons"):
			picker.add_icon_item(theme.get_icon(icon_name, &"EditorIcons"),
				entry["label"], entry["shape"])
		else:
			picker.add_item(entry["label"], entry["shape"])
	picker.item_selected.connect(_on_shape_selected)
	return picker

func _build_output_picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.flat = true
	picker.fit_to_longest_item = false
	for entry in OUTPUTS:
		picker.add_item(entry["label"], entry["output"])
	picker.tooltip_text = "\n".join([OUTPUTS[0]["hint"], OUTPUTS[1]["hint"]])
	picker.item_selected.connect(_on_shape_selected)
	return picker

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
	if settings != null:
		_grid_field.value = float(settings.get_project_metadata(
			PREFS_SECTION, "grid", DEFAULT_GRID))
		_thickness_field.value = float(settings.get_project_metadata(
			PREFS_SECTION, "thickness", DEFAULT_THICKNESS))
		var shape: int = int(settings.get_project_metadata(
			PREFS_SECTION, "shape", Shape.BOX))
		# There is no select_by_id(); an id has to be turned into an index
		# first, and an id that is no longer offered comes back as -1.
		var index: int = _picker.get_item_index(shape)
		if index >= 0:
			_picker.select(index)
		var output: int = int(settings.get_project_metadata(
			PREFS_SECTION, "output", Output.CSG))
		var output_index: int = _output_picker.get_item_index(output)
		if output_index >= 0:
			_output_picker.select(output_index)

func _save_prefs() -> void:
	var settings: EditorSettings = _prefs()
	if settings == null:
		return
	settings.set_project_metadata(PREFS_SECTION, "grid", _grid_field.value)
	settings.set_project_metadata(PREFS_SECTION, "thickness", _thickness_field.value)
	settings.set_project_metadata(PREFS_SECTION, "shape", _picked_shape())
	settings.set_project_metadata(PREFS_SECTION, "output", _picked_output())

func _on_field_changed(_value: float) -> void:
	_save_prefs()

func _on_shape_selected(_index: int) -> void:
	_save_prefs()

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

func _picked_shape() -> int:
	return _picker.get_selected_id() if _picker != null else Shape.BOX

func _picked_output() -> int:
	return _output_picker.get_selected_id() if _output_picker != null else Output.CSG

func _armed() -> bool:
	return _toggle != null and _toggle.button_pressed

func _grid() -> float:
	return _grid_field.value if _grid_field != null else 0.0

func _thickness() -> float:
	return _thickness_field.value if _thickness_field != null else DEFAULT_THICKNESS

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if camera == null or not _armed():
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

## Where a new node goes.
##
## A SIBLING of whatever is selected, not a child of it: every drag selects
## what it just made, so parenting to the selection would thread each solid
## through the last one and build a chain nobody asked for. Siblings keep a run
## of them in one place.
##
## The exception is a collision shape dropped on something that takes one -- an
## Area3D volume, a body -- where being a child IS the point. This project's
## volumes are built exactly that way: Checkpoint, DeathVolume and
## ModifierVolume are all Area3D asking for "whatever CollisionShape3D children
## the spot needs".
func _target_parent(root: Node, collision: bool) -> Node:
	var selected: Node = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Node3D:
			selected = node
			break
	if selected == null or selected == root:
		return root
	if collision and selected is CollisionObject3D:
		return selected
	var parent: Node = selected.get_parent()
	return parent if parent != null else root

func _plan() -> Dictionary:
	var grid: float = _grid()
	var thickness: float = _thickness()
	match _picked_shape():
		Shape.CYLINDER:
			return Geometry.cylinder_from_drag(_anchor, _face, _radius, thickness, grid)
		Shape.SPHERE:
			return Geometry.sphere_from_drag(_anchor, _face, _radius, grid)
		_:
			return Geometry.block_from_drag(_anchor, _face, _extent, thickness, grid)

func _build_csg(plan: Dictionary) -> CSGShape3D:
	match _picked_shape():
		Shape.CYLINDER:
			var cylinder := CSGCylinder3D.new()
			cylinder.name = "Cylinder"
			cylinder.radius = plan["radius"]
			cylinder.height = plan["height"]
			return cylinder
		Shape.SPHERE:
			var sphere := CSGSphere3D.new()
			sphere.name = "Sphere"
			sphere.radius = plan["radius"]
			return sphere
		_:
			var box := CSGBox3D.new()
			box.name = "Box"
			box.size = plan["size"]
			return box

func _build_shape(plan: Dictionary) -> Shape3D:
	match _picked_shape():
		Shape.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = plan["radius"]
			cylinder.height = plan["height"]
			return cylinder
		Shape.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = plan["radius"]
			return sphere
		_:
			var box := BoxShape3D.new()
			box.size = plan["size"]
			return box

## Returns {"node": the Node3D to add to the parent, "inner": a descendant that
## also needs an owner, or null}.
func _build_output(plan: Dictionary, collision: bool, parent: Node) -> Dictionary:
	if not collision:
		var solid: CSGShape3D = _build_csg(plan)
		solid.use_collision = true
		return {"node": solid, "inner": null}

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = _build_shape(plan)
	if parent is CollisionObject3D:
		return {"node": shape, "inner": null}

	# A CollisionShape3D belonging to nothing is inert, and the editor flags it
	# with a warning rather than doing anything about it. Wrapping keeps every
	# drag productive: what comes out is a trigger that already works, and
	# swapping the Area3D for a Checkpoint or a DeathVolume is one field.
	var area := Area3D.new()
	area.name = "Trigger"
	area.add_child(shape)
	return {"node": area, "inner": shape}

func _commit() -> int:
	_dragging = false
	update_overlays()
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return AFTER_GUI_INPUT_STOP

	var plan: Dictionary = _plan()
	var collision: bool = _picked_output() == Output.COLLISION
	var parent: Node = _target_parent(root, collision)
	var built: Dictionary = _build_output(plan, collision, parent)
	var node: Node3D = built["node"]

	# The placement is in world space and the node is about to live under a
	# parent that may be anywhere: without this the whole thing lands wherever
	# the parent's own transform puts it.
	var frame := Transform3D.IDENTITY
	if parent is Node3D:
		frame = (parent as Node3D).global_transform
	node.transform = Geometry.local_placement(frame, plan["transform"] as Transform3D)

	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Draw %s" % node.name)
	undo.add_do_method(parent, "add_child", node, true)
	undo.add_do_method(node, "set_owner", root)
	if built["inner"] != null:
		# A descendant with no owner is dropped when the scene is saved.
		undo.add_do_method(built["inner"], "set_owner", root)
	undo.add_do_reference(node)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()

	var selection: EditorSelection = EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	# Disarm, because the next thing anyone does is pull the thing they just
	# drew to height -- and while the tool is armed this plugin eats the bare
	# left click, so the handles cannot be grabbed. Selecting the new node
	# without disarming hands over a gizmo that does not answer.
	_toggle.set_pressed_no_signal(false)
	return AFTER_GUI_INPUT_STOP

func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _dragging:
		return
	var camera: Camera3D = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	if camera == null:
		return
	var screen := PackedVector2Array()
	for corner in _footprint():
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
	if _picked_shape() == Shape.BOX:
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
