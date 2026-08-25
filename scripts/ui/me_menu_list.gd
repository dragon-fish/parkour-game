class_name MeMenuList
extends Control

# ME-styled vertical menu list: red panel items with white text, a full-width
# white "selected" bar that slides between items, and the spec's edge-wave
# shader on both the shared red backdrop (full amplitude) and the selection
# bar (half amplitude -- "白条动得比红列更轻"). Reused by PauseUi and the
# main menu.
#
# STRUCTURE (v2, after the first windowed look): plain LOCAL children in
# explicit draw order -- backdrop, selection bar, hover preview, then a
# VBoxContainer holding the labels ON TOP. The first version parented
# `top_level` ColorRects into the vbox and trusted a headless "empirical
# verification" that labels drew above them; the first real capture showed
# the exact opposite -- top_level items draw over the subtree, and the only
# text ever visible was peeking through the wave shader's eroded edge.
# Local children need no global_position bookkeeping and follow the parent's
# entrance slide for free.

signal chosen(index: int)

const ITEM_HEIGHT := 56.0
const BACKDROP_AMPLITUDE_PX := 8.0
const HOVER_NUDGE_PX := 12.0
const TWEEN_TIME := 0.12
const _SELECTED_TEXT_COLOR := Color(0.08, 0.08, 0.1)
const ENTRANCE_STAGGER := 0.03
const ENTRANCE_OFFSET_PX := 40.0

var _backdrop: ColorRect
var _selection_bar: ColorRect
var _hover_preview: ColorRect
var _items_box: VBoxContainer
var _labels: Array[Label] = []
var _selected_index: int = 0
var _bar_tween: Tween
var _entrance_tween: Tween

func _ready() -> void:
	theme = MeTheme.ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = _make_bar(MeTheme.BRAND_RED, BACKDROP_AMPLITUDE_PX)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_selection_bar = _make_bar(Color.WHITE, BACKDROP_AMPLITUDE_PX * 0.5)
	_hover_preview = _make_bar(Color(1.0, 1.0, 1.0, 0.18), 0.0)
	_hover_preview.visible = false
	_items_box = VBoxContainer.new()
	_items_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A full-height column centres its items vertically (ME's own layout).
	_items_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_items_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items_box)
	resized.connect(_sync_widths)
	call_deferred("_sync_widths")

func _make_bar(color: Color, amplitude_px: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = color
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
		var padding := StyleBoxEmpty.new()
		padding.content_margin_left = 28.0
		padding.content_margin_right = 28.0
		label.add_theme_stylebox_override("normal", padding)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_entered.connect(_on_item_hover.bind(i, true))
		label.mouse_exited.connect(_on_item_hover.bind(i, false))
		label.gui_input.connect(_on_item_gui_input.bind(i))
		# The vbox recentres rows whenever the column's height changes (the
		# full-height ME layout centres its items), and the selection bar
		# must chase them -- rect change is the honest signal.
		label.item_rect_changed.connect(_sync_widths)
		_items_box.add_child(label)
		_labels.append(label)

	_selected_index = 0
	_refresh_colors()
	call_deferred("_sync_widths")

## The stagger-in (✅ ease-in-out per the owner's direction). Labels slide
## from the left and fade up, ENTRANCE_STAGGER apart.
func play_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = create_tween()
	_entrance_tween.set_parallel(true)
	for i in _labels.size():
		var label := _labels[i]
		label.modulate.a = 0.0
		label.position.x = -ENTRANCE_OFFSET_PX
		_entrance_tween.tween_property(label, "modulate:a", 1.0, TWEEN_TIME) \
			.set_delay(i * ENTRANCE_STAGGER).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_entrance_tween.tween_property(label, "position:x", 0.0, TWEEN_TIME) \
			.set_delay(i * ENTRANCE_STAGGER).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Jumps every item straight to its settled state.
func skip_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	for label in _labels:
		label.modulate.a = 1.0
		label.position.x = 0.0

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
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hover_preview.visible = entered and index != _selected_index
	if _hover_preview.visible:
		_place_bar(_hover_preview, index)

## Keyboard nav. is_visible_in_tree(), not `visible`: PauseUi is a
## CanvasLayer whose own flag never cascades -- see that file's history.
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
	_slide_selection_bar()

func _refresh_colors() -> void:
	for i in _labels.size():
		var selected := i == _selected_index
		_labels[i].add_theme_color_override("font_color", _SELECTED_TEXT_COLOR if selected else Color.WHITE)

func _slide_selection_bar() -> void:
	if _labels.is_empty():
		return
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_size_bar(_selection_bar, _selected_index)
	_bar_tween = _selection_bar.create_tween()
	_bar_tween.tween_property(_selection_bar, "position:y", _row_y(_selected_index), TWEEN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## All LOCAL space now: a row's y inside the items box equals its y in this
## control (the box is full-rect at zero offset).
func _row_y(index: int) -> float:
	return _labels[index].position.y

func _size_bar(bar: ColorRect, index: int) -> void:
	bar.size = Vector2(size.x, _labels[index].size.y)
	if bar.material is ShaderMaterial:
		(bar.material as ShaderMaterial).set_shader_parameter("width_px", maxf(size.x, 1.0))

func _place_bar(bar: ColorRect, index: int) -> void:
	_size_bar(bar, index)
	bar.position = Vector2(0.0, _row_y(index))

func _sync_widths() -> void:
	if not is_inside_tree():
		return
	if _backdrop.material is ShaderMaterial:
		(_backdrop.material as ShaderMaterial).set_shader_parameter("width_px", maxf(size.x, 1.0))
	if not _labels.is_empty():
		_place_bar(_selection_bar, _selected_index)
