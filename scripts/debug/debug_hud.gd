class_name DebugHud
extends CanvasLayer

# Tab-toggled readout of everything needed to judge whether a tuning change
# did what was intended.

@export var player: Player

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			visible = not visible

func _process(_delta: float) -> void:
	if not visible or player == null or player.state_machine == null:
		return
	var pos := player.global_position
	_label.text = "\n".join([
		"state      %s" % player.state_machine.current_name,
		"speed h    %.2f m/s" % player.horizontal_speed(),
		"speed v    %.2f m/s" % player.velocity.y,
		"position   (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z],
		"grounded   %s" % ("yes" if player.grounded else "no"),
		"last land  %.2f m/s" % player.last_landing_speed,
		"fps        %d" % Engine.get_frames_per_second(),
		"",
		"Tab HUD   F1 tuning   R reset   Esc release mouse",
	])
