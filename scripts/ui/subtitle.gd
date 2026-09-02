class_name Subtitle
extends CanvasLayer

# One line of player-facing text along the bottom of the screen, faded in,
# held, faded out. THIS IS THE GAME TALKING TO THE PLAYER -- tutorial lines,
# story. A report that something HAPPENED (a checkpoint saved, an item taken)
# is not a subtitle; that belongs in the corner toast, not here.
#
# Lives on the PLAYER next to Crosshair and ScreenEffects, for the same
# reason those do: it talks about what happened to this player, and must
# survive a level change.

## PROJECT-DEFINED feel values: quick in, readable hold, soft out.
const FADE_IN := 0.15
const HOLD := 2.0
const FADE_OUT := 0.5

var _label: Label
var _tween: Tween

func _ready() -> void:
	layer = 1
	_label = Label.new()
	_label.name = "Line"
	# The lower third of the screen, centred -- present without sitting on
	# the crosshair.
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.72
	_label.anchor_bottom = 0.80
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = 22
	# The dark outline earns its keep the same way the crosshair's dark ring
	# does: this project's blockout is largely white.
	settings.outline_size = 5
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.6)
	_label.label_settings = settings
	_label.modulate.a = 0.0
	add_child(_label)

## Shows `text` through the fade-hold-fade cycle. A call while a line is
## still up replaces it and restarts the cycle.
func show_text(text: String) -> void:
	_label.text = text
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)

# --- read by the tests -----------------------------------------------------

func showing() -> bool:
	return _label.modulate.a > 0.0

func text() -> String:
	return _label.text
