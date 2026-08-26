class_name MeSettingsMenu
extends Control

# ME-styled settings page: three-part composition per the spec -- a left
# column of TEXT_BLUE labels, a middle column of controls (a stepper pair for
# window_mode/window_size, red-filled HSliders for sensitivity/fov/volume), a
# top-right description Label that reflects whichever row is currently
# hovered, and a bottom-right row of three red skewed buttons (默认/保存设置/
# 取消). Pushed in place of PauseUi's menu list on 设置; the main menu is
# expected to reuse this same Control later.
#
# Edits happen on a WORKING COPY loaded fresh from SettingsStore each time the
# page opens (see reload()) -- nothing touches disk or the live engine until
# 保存设置 is pressed. 取消 and 默认 both leave the file untouched; 默认 only
# resets the in-memory copy and the on-screen controls, it does NOT save
# (spec: "不落盘").

signal closed

## window_mode row's two option values, in stepper order.
const WINDOW_MODES := ["windowed", "fullscreen"]
const WINDOW_MODE_LABELS := {"windowed": "窗口化", "fullscreen": "全屏"}

## window_size row's presets, in stepper order (ascending). Includes
## SettingsStore.defaults()'s own window_size (1440x810) -- a never-saved page
## must display the size that is actually applied, not the nearest lookalike.
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1440, 810), Vector2i(1600, 900), Vector2i(1920, 1080)]

const _ROWS := [
	{"key": "window_mode", "label": "窗口模式", "desc": "切换窗口化显示或全屏显示。"},
	{"key": "window_size", "label": "窗口大小", "desc": "选择窗口化模式下的分辨率，全屏时不可用。"},
	{"key": "sensitivity", "label": "鼠标灵敏度", "desc": "调整视角转动的鼠标灵敏度。"},
	{"key": "fov", "label": "视野 FOV", "desc": "调整摄像机基准视野角度。"},
	{"key": "volume_db", "label": "总音量", "desc": "调整主音量大小（分贝）。"},
]

const _DEFAULT_DESCRIPTION := "将鼠标移到左侧设置项上查看说明。"
const _ROW_HEIGHT := 40.0

var _working: Dictionary
var _description_label: Label
var _rows_parent: VBoxContainer
var _buttons_parent: Control
## key -> Label, the stepper rows' current-value display.
var _stepper_value_labels: Dictionary = {}
## key -> [left Button, right Button] -- window_size's pair gets dimmed/
## disabled while window_mode is fullscreen.
var _stepper_buttons: Dictionary = {}
## key -> HSlider, the three slider rows.
var _sliders: Dictionary = {}
## key -> Label, the sliders' current-value display.
var _slider_value_labels: Dictionary = {}

func _ready() -> void:
	theme = MeTheme.ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_working = SettingsStore.load_settings()
	_build_ui()
	_refresh_controls()

## Re-reads the settings file into a fresh working copy and syncs every
## control to it. Called by PauseUi each time the settings page is shown, so
## a previous visit's 取消/保存设置 is never stale on reopen.
func reload() -> void:
	_working = SettingsStore.load_settings()
	_refresh_controls()

func _build_ui() -> void:
	# Full-screen wash behind the panel (the reference's pale field).
	var wash := ColorRect.new()
	wash.color = Color(0.93, 0.95, 0.98, 0.98)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	# The reference's grey-blue page title, top-left of screen, above the
	# panel: 「设置」.
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	title.position = Vector2(220.0, 90.0)
	add_child(title)

	# Centred, hairline-bordered panel -- the composition's anchor.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MeTheme.panel_style())
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -620.0
	panel.offset_right = 620.0
	panel.offset_top = -300.0
	panel.offset_bottom = 300.0
	add_child(panel)

	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)

	var rows_box := VBoxContainer.new()
	rows_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rows_box.position = Vector2(56.0, 56.0)
	rows_box.custom_minimum_size = Vector2(640.0, 0.0)
	rows_box.add_theme_constant_override("separation", 26.0)
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rows_box)

	_description_label = Label.new()
	_description_label.text = _DEFAULT_DESCRIPTION
	_description_label.add_theme_color_override("font_color", MeTheme.TEXT_BLUE)
	_description_label.add_theme_font_size_override("font_size", 20)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_description_label.position = Vector2(-400.0, 56.0)
	_description_label.custom_minimum_size = Vector2(344.0, 140.0)
	inner.add_child(_description_label)
	_rows_parent = rows_box
	_buttons_parent = inner

	for row in _ROWS:
		var key: String = row["key"]
		var desc: String = row["desc"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 18.0)
		_rows_parent.add_child(line)

		var label := Label.new()
		label.text = row["label"]
		label.custom_minimum_size = Vector2(140.0, _ROW_HEIGHT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", MeTheme.TEXT_BLUE)
		label.add_theme_font_size_override("font_size", 20)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_entered.connect(_show_description.bind(desc))
		line.add_child(label)

		if key == "window_mode" or key == "window_size":
			_build_stepper(line, key, desc)
		else:
			_build_slider(line, key, desc)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	buttons.position = Vector2(-436.0, -100.0)
	buttons.custom_minimum_size = Vector2(400.0, 48.0)
	buttons.add_theme_constant_override("separation", 12.0)
	_buttons_parent.add_child(buttons)

	buttons.add_child(_make_bottom_button("默认", _on_default_pressed))
	buttons.add_child(_make_bottom_button("保存设置", _on_save_pressed))
	buttons.add_child(_make_bottom_button("取消", _on_cancel_pressed))

func _make_bottom_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120.0, 44.0)
	button.add_theme_stylebox_override("normal", MeTheme.button_style(MeTheme.BRAND_RED))
	button.add_theme_stylebox_override("hover", MeTheme.button_style(MeTheme.BRAND_RED.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", MeTheme.button_style(MeTheme.BRAND_RED.darkened(0.12)))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.pressed.connect(handler)
	return button

func _build_stepper(line: HBoxContainer, key: String, desc: String) -> void:
	var left := _arrow_button("←")
	left.pressed.connect(_on_stepper_step.bind(key, -1))
	left.mouse_entered.connect(_show_description.bind(desc))
	line.add_child(left)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(160.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", Color(0.16, 0.28, 0.45))
	value_label.mouse_filter = Control.MOUSE_FILTER_STOP
	value_label.mouse_entered.connect(_show_description.bind(desc))
	line.add_child(value_label)
	_stepper_value_labels[key] = value_label

	var right := _arrow_button("→")
	right.pressed.connect(_on_stepper_step.bind(key, 1))
	right.mouse_entered.connect(_show_description.bind(desc))
	line.add_child(right)

	_stepper_buttons[key] = [left, right]

## The reference's red arrow glyphs: no box, red text, brightening on hover.
func _arrow_button(glyph: String) -> Button:
	var button := Button.new()
	button.text = glyph
	button.flat = true
	button.custom_minimum_size = Vector2(40.0, 0.0)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", MeTheme.BRAND_RED)
	button.add_theme_color_override("font_hover_color", MeTheme.BRAND_RED.lightened(0.25))
	button.add_theme_color_override("font_pressed_color", MeTheme.BRAND_RED.darkened(0.2))
	button.add_theme_color_override("font_disabled_color", Color(0.6, 0.65, 0.72))
	return button

func _build_slider(line: HBoxContainer, key: String, desc: String) -> void:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(220.0, 0.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match key:
		"sensitivity":
			slider.min_value = 0.0005
			slider.max_value = 0.01
			slider.step = 0.0001
		"fov":
			slider.min_value = 60.0
			slider.max_value = 110.0
			slider.step = 1.0
		"volume_db":
			slider.min_value = -40.0
			slider.max_value = 6.0
			slider.step = 0.5

	MeTheme.dress_slider(slider)

	slider.mouse_entered.connect(_show_description.bind(desc))
	slider.value_changed.connect(_on_slider_changed.bind(key))
	line.add_child(slider)
	_sliders[key] = slider

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(80.0, 0.0)
	value_label.add_theme_color_override("font_color", MeTheme.TEXT_BLUE)
	line.add_child(value_label)
	_slider_value_labels[key] = value_label

## Esc anywhere on this page = 取消 (✅ the owner could not find a way back
## from the main menu's settings). Runs on the page itself so BOTH hosts get
## it; child controls see unhandled input before the PauseUi autoload, so
## its own Esc fallback never double-fires.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()

func _show_description(desc: String) -> void:
	_description_label.text = desc

func _on_stepper_step(key: String, delta: int) -> void:
	if key == "window_mode":
		var index := WINDOW_MODES.find(_working.window_mode)
		if index < 0:
			index = 0
		_working.window_mode = WINDOW_MODES[wrapi(index + delta, 0, WINDOW_MODES.size())]
	elif key == "window_size":
		if _working.window_mode == "fullscreen":
			return
		var index := _window_size_index(_working.window_size)
		_working.window_size = WINDOW_SIZES[wrapi(index + delta, 0, WINDOW_SIZES.size())]
	_refresh_controls()

func _on_slider_changed(value: float, key: String) -> void:
	_working[key] = value
	_refresh_slider_label(key)

## 默认: resets the working copy (and every control) to SettingsStore.defaults()
## -- NOT saved until 保存设置 is pressed afterwards.
func _on_default_pressed() -> void:
	_working = SettingsStore.defaults()
	_refresh_controls()

## 保存设置: writes the working copy to disk and applies it live.
func _on_save_pressed() -> void:
	SettingsStore.save_settings(_working)
	SettingsStore.apply_global(_working)
	_sync_window_memory()
	_apply_to_live_player()
	closed.emit()

## The settings-page half of the window-size ownership rule (see
## settings_store.gd's apply_global() and window_memory.gd's own header
## comment): a deliberate 保存设置 choice has to update WindowMemory's own
## file too, or the very next boot would see user://window.cfg still holding
## the OLD dragged size, defer to it per that rule, and silently discard the
## choice just made here. Writes only the "size" key WindowMemory owns --
## "position" is left alone, since this page has no opinion on where the
## window sits on screen.
##
## Guarded the same way WindowMemory._ready() and apply_global() are: skipped
## in headless (no window to speak of, and this is also what keeps the
## headless test suite from ever touching the author's real
## user://window.cfg when these save/cancel/default tests run).
func _sync_window_memory() -> void:
	if DisplayServer.get_name() in ["headless", "embedded"]:
		return
	var cfg := ConfigFile.new()
	cfg.load(WindowMemory.PATH)  # preserve "position" if present; ignored on first run
	cfg.set_value("window", "size", _working.window_size)
	cfg.save(WindowMemory.PATH)

## 取消: discards the working copy by reloading from disk (a no-op if nothing
## was ever saved) -- the file itself is never touched.
func _on_cancel_pressed() -> void:
	_working = SettingsStore.load_settings()
	closed.emit()

## Nice-to-have: Arena (the only level type so far) exports its Player
## directly, so the live camera can pick up the new sensitivity/FOV without
## waiting for a respawn. Duck-typed so a level without that shape (or no
## current scene at all, e.g. headless tests) is silently skipped -- Player.
## setup() already applies SettingsStore.load_settings() on its own, so a
## level that reloads/respawns picks this up regardless. is_instance_valid()
## guards the same way arena.gd itself guards this exact reference -- the
## player may have been freed (e.g. a reset mid-flight) without Arena's
## `player` export having been cleared to null.
func _apply_to_live_player() -> void:
	var current := get_tree().current_scene
	if current == null or not ("player" in current):
		return
	var player = current.player
	if not is_instance_valid(player) or not ("config" in player) or player.config == null:
		return
	SettingsStore.apply_to_config(_working, player.config)

func _window_size_index(size: Vector2i) -> int:
	var index := WINDOW_SIZES.find(size)
	return index if index >= 0 else 0

func _refresh_controls() -> void:
	_stepper_value_labels["window_mode"].text = WINDOW_MODE_LABELS.get(_working.window_mode, _working.window_mode)
	_stepper_value_labels["window_size"].text = "%d×%d" % [_working.window_size.x, _working.window_size.y]

	for key in ["sensitivity", "fov", "volume_db"]:
		(_sliders[key] as HSlider).set_value_no_signal(_working[key])
		_refresh_slider_label(key)

	_update_window_size_enabled()

func _refresh_slider_label(key: String) -> void:
	var label: Label = _slider_value_labels[key]
	match key:
		"sensitivity":
			label.text = "%.4f" % _working.sensitivity
		"fov":
			label.text = "%.0f°" % _working.fov
		"volume_db":
			label.text = "%.1f dB" % _working.volume_db

func _update_window_size_enabled() -> void:
	var enabled: bool = _working.window_mode != "fullscreen"
	var buttons: Array = _stepper_buttons["window_size"]
	var target_modulate := Color(1.0, 1.0, 1.0, 1.0) if enabled else Color(1.0, 1.0, 1.0, 0.4)
	for button in buttons:
		(button as Button).disabled = not enabled
		(button as Button).modulate = target_modulate
	(_stepper_value_labels["window_size"] as Label).modulate = target_modulate
