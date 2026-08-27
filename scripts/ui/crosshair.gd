class_name Crosshair
extends CanvasLayer

# A plain white dot at the centre of the screen, matching the original's.
#
# It is not an aiming reticle -- nothing in this game is aimed. It exists
# because a first-person camera with no fixed point of reference is genuinely
# nauseating to play for long, and because a dot is the cheapest way to read
# which way the body is facing during a wall run or a turn.
#
# Lives on the PLAYER rather than the level, next to ScreenEffects, for the
# same reason that one does: it describes the player's own view, and must
# survive a level change.

## PROJECT-DEFINED. Small enough to read as a point rather than a target.
const RADIUS := 2.0

## Assigned by tools/player_builder.gd. Optional so a hand-built player in a
## headless test does not need one.
@export var player: Player

var _dot: Control

func _ready() -> void:
	layer = 1
	_dot = Control.new()
	_dot.name = "Dot"
	_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	add_child(_dot)
	get_viewport().size_changed.connect(_dot.queue_redraw)

func _draw_dot() -> void:
	var centre: Vector2 = _dot.size * 0.5
	# A hairline of dark behind it, so the dot survives being drawn over
	# white geometry -- which this project's blockout is largely made of.
	_dot.draw_circle(centre, RADIUS + 1.0, Color(0.0, 0.0, 0.0, 0.35))
	_dot.draw_circle(centre, RADIUS, Color.WHITE)

## Shown only while the player actually has control: hidden for the death
## cutscene (which takes the input gate) and while the cursor is released for
## the tuning panel, where a dot over a slider is just clutter.
func _process(_delta: float) -> void:
	if _dot == null:
		return
	var wanted: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and (player == null or not player.is_input_locked())
	if _dot.visible != wanted:
		_dot.visible = wanted
