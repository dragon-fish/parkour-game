class_name MeMenuList
extends VBoxContainer

# ME-styled vertical menu list: red panel items with white text, a full-width
# white "selected" bar that slides between items, and the spec's edge-wave
# shader on both the shared red backdrop (full amplitude) and the selection
# bar (half amplitude -- "白条动得比红列更轻"). Reused by PauseUi (Task 3) and,
# later, the main menu / settings page.
#
# STRUCTURAL NOTE: the backdrop/selection-bar/hover-preview ColorRects are all
# `top_level = true`, verified empirically against Godot 4.7's Container
# layout: a top_level Control does not consume a row in the vbox's own
# vertical stacking, and its `position`/`size` live in the SAME space as this
# control's own `global_position`/`size` rather than relative to it. They are
# added FIRST so the item Labels, added by set_items() after, draw and
# hit-test on top of them.

signal chosen(index: int)

## Row height for each item.
const ITEM_HEIGHT := 56.0
## Wave amplitude for the shared red backdrop; the selection bar runs at
## half this (see the header comment).
const BACKDROP_AMPLITUDE_PX := 8.0
## How far a hovered item's label nudges right, and how long both that nudge
## and the selection bar's slide between items take.
const HOVER_NUDGE_PX := 12.0
const TWEEN_TIME := 0.12

## "深色文字" for the selected item -- the spec pins the bar to white but
## does not pin an exact dark, so this is a knob, not a spec value.
const _SELECTED_TEXT_COLOR := Color(0.08, 0.08, 0.1)

var _backdrop: ColorRect
var _selection_bar: ColorRect
var _hover_preview: ColorRect
var _labels: Array[Label] = []
var _selected_index: int = 0
var _bar_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = _make_bar(MeTheme.BRAND_RED, BACKDROP_AMPLITUDE_PX)
	_selection_bar = _make_bar(Color.WHITE, BACKDROP_AMPLITUDE_PX * 0.5)
	_hover_preview = _make_bar(Color(1.0, 1.0, 1.0, 0.18), 0.0)
	_hover_preview.visible = false
	resized.connect(_sync_overlays)
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_sync_overlays)
	# One layout pass has to happen before global_position/size are real.
	call_deferred("_sync_overlays")

func _make_bar(color: Color, amplitude_px: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = color
	bar.top_level = true
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if amplitude_px > 0.0:
		bar.material = MeTheme.wave_material(amplitude_px)
	add_child(bar)
	return bar

## Replaces the current items and resets selection to the first one.
func set_items(items: Array[String]) -> void:
	for label in _labels:
		label.queue_free()
	_labels.clear()

	for i in items.size():
		var label := Label.new()
		label.text = items[i]
		label.custom_minimum_size = Vector2(0.0, ITEM_HEIGHT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", 28)
		# Left/right breathing room without touching position (position is
		# reserved for the hover nudge below).
		var padding := StyleBoxEmpty.new()
		padding.content_margin_left = 28.0
		padding.content_margin_right = 28.0
		label.add_theme_stylebox_override("normal", padding)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_entered.connect(_on_item_hover.bind(i, true))
		label.mouse_exited.connect(_on_item_hover.bind(i, false))
		label.gui_input.connect(_on_item_gui_input.bind(i))
		add_child(label)
		_labels.append(label)

	_selected_index = 0
	_refresh_colors()
	call_deferred("_sync_overlays")

func _on_item_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_select(index)
		chosen.emit(index)

func _on_item_hover(index: int, entered: bool) -> void:
	if index >= _labels.size():
		return
	var label := _labels[index]
	var target_x := HOVER_NUDGE_PX if entered else 0.0
	var tween := label.create_tween()
	tween.tween_property(label, "position:x", target_x, TWEEN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Never on the already-selected row -- it already has the solid bar.
	_hover_preview.visible = entered and index != _selected_index
	if _hover_preview.visible:
		_position_bar(_hover_preview, index)

## Keyboard nav, guarded on visibility so a hidden/paused-off list (e.g. while
## the game itself is playing, not the pause menu) does not eat Up/Down/Enter
## meant for gameplay -- PauseUi only shows this list while it is the thing
## receiving input.
##
## is_visible_in_tree(), not the plain `visible` property: this node's
## PROCESS_MODE_ALWAYS is inherited from PauseUi (a CanvasLayer), and
## CanvasLayer is not a CanvasItem -- toggling ITS `visible` never cascades
## down to set this control's own `visible` flag, so a plain `visible` check
## here would read true forever regardless of whether PauseUi ever shows this
## list (caught in review: this control kept consuming every Up/Down/Enter
## in normal, unpaused play). is_visible_in_tree() walks the actual Control
## ancestor chain PauseUi._set_shown() toggles, so it can't be fooled by a
## parent that never touches this node directly.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _labels.is_empty():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_DOWN:
			_select((_selected_index + 1) % _labels.size())
			get_viewport().set_input_as_handled()
		KEY_UP:
			_select((_selected_index - 1 + _labels.size()) % _labels.size())
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			chosen.emit(_selected_index)
			get_viewport().set_input_as_handled()

func _select(index: int) -> void:
	_selected_index = index
	_refresh_colors()
	_move_selection_bar()

func _refresh_colors() -> void:
	for i in _labels.size():
		var selected := i == _selected_index
		_labels[i].add_theme_color_override("font_color", _SELECTED_TEXT_COLOR if selected else Color.WHITE)

func _move_selection_bar() -> void:
	if _labels.is_empty():
		return
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_position_bar_size(_selection_bar, _selected_index)
	_bar_tween = _selection_bar.create_tween()
	_bar_tween.tween_property(_selection_bar, "position:y", _bar_target_y(_selected_index), TWEEN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _bar_target_y(index: int) -> float:
	return global_position.y + _labels[index].position.y

## Snaps a bar's rect to a given row immediately (no tween) -- used for the
## hover preview, and for the selection bar's width/height, which never
## animate, only its y does (see _move_selection_bar()).
func _position_bar_size(bar: ColorRect, index: int) -> void:
	bar.size = Vector2(size.x, _labels[index].size.y)
	if bar.material is ShaderMaterial:
		(bar.material as ShaderMaterial).set_shader_parameter("width_px", maxf(size.x, 1.0))

func _position_bar(bar: ColorRect, index: int) -> void:
	_position_bar_size(bar, index)
	bar.position = Vector2(global_position.x, _bar_target_y(index))

func _sync_overlays() -> void:
	if not is_inside_tree():
		return
	_backdrop.position = global_position
	_backdrop.size = size
	if _backdrop.material is ShaderMaterial:
		(_backdrop.material as ShaderMaterial).set_shader_parameter("width_px", maxf(size.x, 1.0))
	if not _labels.is_empty():
		_position_bar(_selection_bar, _selected_index)
