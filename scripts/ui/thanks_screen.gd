class_name ThanksScreen
extends Control

# The end of the tutorial: a held card, then back to the front door. Built in
# code like every other screen in this project (pause_ui.gd, settings_menu.gd,
# main_menu.gd); scenes/ui/thanks_for_playing.tscn is a one-node root with this
# script attached.
#
# THIS SCENE IS NEITHER A LEVEL NOR THE MAIN MENU, and two things that every
# other screen gets for free therefore have to be said here:
#
#   The mouse. Only MainMenu._ready() and Arena.capture_mouse set the mode, so
#   arriving here from a level would leave the cursor captured.
#
#   Esc. PauseUi's own guard exempts the main menu by type, not this, so Esc
#   would open a pause menu over a scene with no player -- every row of which
#   does nothing. Esc is treated as "leave" instead, and consumed.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Seam for the exit, same shape as MainMenu._change_scene: a test can observe
## the request without a real change_scene_to_file() swapping GUT's own runner
## scene out mid-suite.
var _change_scene: Callable = Callable(self, "_real_change_scene")

## Set the moment leaving starts. The white transition spans several frames,
## and a second request underneath one already in flight swaps the tree twice.
var _leaving: bool = false

func _real_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MeTheme.ui_theme()
	# The ROOT must not eat clicks: a full-rect Control defaults to
	# MOUSE_FILTER_STOP and would consume every press as GUI input before
	# _unhandled_input ever saw it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.96, 0.96, 0.94)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	add_child(MeTheme.paper_noise_layer())

	var title := Label.new()
	title.text = "感谢试玩"
	title.add_theme_font_size_override("font_size", 64)
	MeTheme.dress_over_anything(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.42
	title.anchor_bottom = 0.42
	title.offset_bottom = 90.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var line := Label.new()
	line.text = "她还在跑。"
	line.add_theme_font_size_override("font_size", 22)
	MeTheme.dress_over_anything(line)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.56
	line.anchor_bottom = 0.56
	line.offset_bottom = 40.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	add_child(MeTheme.footer_label("按任意键返回主菜单"))

func _unhandled_input(event: InputEvent) -> void:
	var is_key_press := event is InputEventKey \
		and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var is_click := event is InputEventMouseButton \
		and (event as InputEventMouseButton).pressed
	if not (is_key_press or is_click):
		return
	get_viewport().set_input_as_handled()
	_leave()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	# Normal transitions are WHITE (the transition-colour convention; black is
	# reserved for a death). Headless keeps the bare seam for the tests.
	if DisplayServer.get_name() == "headless":
		_change_scene.call(MAIN_MENU_SCENE)
		return
	PauseUi.run_white_transition(load(MAIN_MENU_SCENE), 0.5)
