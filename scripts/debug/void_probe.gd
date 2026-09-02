class_name VoidProbe
extends CanvasLayer

# TEMPORARY. A readout for hand-testing the torus plain, and nothing else --
# delete this file and its node when the wrap has been judged by eye.
#
# It exists because the three questions the plain has to answer cannot be
# answered by a headless test:
#
#   Is momentum preserved?    Watch the speed line across a crossing. It must
#                             not so much as flicker.
#   Does anything flash?      Watch the picture, not this panel.
#   Do the spring bones fire? Watch the hair. A VRM spring bone derives
#                             velocity from world position, so a teleport
#                             reads to it as a hundred metres in one frame.
#
# The crossing counter is here because a correct wrap is INVISIBLE: the plain
# is periodic, so the world looks identical either side of a seam. Without a
# number on screen there is no way to tell a crossing from an ordinary stride.

var player: Player
var wrap: TorusWrap

var _label: Label
var _crossings: int = 0
var _last_speed: float = 0.0
var _speed_at_crossing: float = -1.0
var _speed_after_crossing: float = -1.0

func _ready() -> void:
	layer = 8
	_label = Label.new()
	_label.name = "Readout"
	_label.position = Vector2(18.0, 18.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = 16
	settings.outline_size = 5
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.75)
	_label.label_settings = settings
	add_child(_label)
	if wrap != null:
		wrap.wrapped.connect(_on_wrapped)

func _process(_delta: float) -> void:
	if player == null:
		return
	var speed: float = player.horizontal_speed()
	var pos: Vector3 = player.global_position
	var lines := PackedStringArray()
	lines.append("x %7.2f   z %7.2f   y %6.2f" % [pos.x, pos.z, pos.y])
	lines.append("speed %6.2f m/s" % speed)
	lines.append("crossings %d" % _crossings)
	if _speed_at_crossing >= 0.0:
		# THE NUMBER THAT MATTERS. A wrap moves the body and must not touch
		# velocity; these two are sampled either side of the same crossing, so
		# any difference is momentum the seam ate.
		lines.append("last seam: %.3f -> %.3f  (delta %+.4f)" % [
			_speed_at_crossing, _speed_after_crossing,
			_speed_after_crossing - _speed_at_crossing])
	_label.text = "\n".join(lines)
	_last_speed = speed

func _on_wrapped(_offset: Vector3) -> void:
	_crossings += 1
	_speed_at_crossing = _last_speed
	# Sampled on the frame AFTER the shift, so the reading covers the teleport
	# itself rather than the frame before it.
	await get_tree().process_frame
	if is_instance_valid(player):
		_speed_after_crossing = player.horizontal_speed()
