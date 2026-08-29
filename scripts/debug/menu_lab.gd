class_name MenuLab
extends Control

# A workbench for the main menu, because parts of it cannot be looked at.
#
# THE RUN LASTS ABOUT A SECOND AND A HALF and then the level takes over, which
# is not long enough to aim a camera against. Everything here exists to stop
# time being the thing you are fighting: each stage can be jumped to, held
# open indefinitely, and slowed down.
#
# It drives the real MainMenu rather than a copy of it. A workbench that runs
# its own version of the thing is a workbench that agrees with itself and
# nothing else.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## The slow-motion steps, in the order the bracket keys walk them.
const TIME_SCALES: Array[float] = [1.0, 0.5, 0.25, 0.1]

var _menu: MainMenu
var _legend: Label
var _scale_index: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_legend()
	_rebuild()

func _exit_tree() -> void:
	# Engine-wide, so it is this node's to give back. A lab left at a tenth
	# speed makes the next scene look broken with nothing to explain it.
	Engine.time_scale = 1.0

## Fresh menu, from its own first frame. Rebuilt rather than reset because the
## opening state involves a solved framing, a body mount and a pile of tweens,
## and a partial reset is how a workbench starts lying to you.
func _rebuild() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	# The 开始 button must not swap the scene out from under the lab. Same
	# seam the menu's own tests use.
	_menu._change_scene = func(_path: String) -> void:
		print("[lab] 开始 pressed; the scene change is stubbed out here")
	add_child(_menu)
	move_child(_menu, 0)

func _build_legend() -> void:
	_legend = Label.new()
	_legend.position = Vector2(16.0, 16.0)
	_legend.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	_legend.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0))
	_legend.add_theme_constant_override("outline_size", 5)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_legend)
	_refresh_legend()

func _refresh_legend() -> void:
	_legend.text = "\n".join([
		"MENU LAB",
		"1  opening hold (crouched close-up)",
		"2  play the entrance from the click",
		"3  jump to settled (walking)",
		"4  the loading run, held open",
		# String.num(), not a "%g" format. GDScript's format operator has no `g`
		# conversion -- it throws rather than printing the number. Already
		# written down once, in StatusSpec.summary(), and repeated here anyway.
		"[ ]  slower / faster    now " + String.num(Engine.time_scale, 3) + "x",
		"R  rebuild from scratch",
	])

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1:
			_rebuild()
		KEY_2:
			# The click, without waiting for the prompt to breathe at you.
			if is_instance_valid(_menu):
				_menu._begin_show()
		KEY_3:
			if is_instance_valid(_menu):
				_menu._skip_entrance()
		KEY_4:
			# Settled first: the run is what the settled menu DOES, and
			# playing it over the opening shot would frame from the wrong
			# place and tell you the camera was broken.
			if is_instance_valid(_menu):
				_menu._skip_entrance()
				_menu.play_run_look()
		KEY_R:
			_rebuild()
		KEY_BRACKETLEFT:
			_step_time(1)
		KEY_BRACKETRIGHT:
			_step_time(-1)
	_refresh_legend()

func _step_time(direction: int) -> void:
	_scale_index = clampi(_scale_index + direction, 0, TIME_SCALES.size() - 1)
	Engine.time_scale = TIME_SCALES[_scale_index]
