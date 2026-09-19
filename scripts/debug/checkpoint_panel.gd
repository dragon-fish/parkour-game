class_name CheckpointPanel
extends CanvasLayer

## DEBUG. F2: every checkpoint of the level in its own order, the active one
## ticked; clicking one respawns there (Arena.debug_jump_to). Rebuilt each
## time it opens, so the tick follows the last one touched.

const WIDTH := 360.0

var _panel: PanelContainer
var _list: VBoxContainer


func _ready() -> void:
	layer = 60
	visible = false
	_panel = PanelContainer.new()
	add_child(_panel)
	# AFTER add_child: a parented Control keeps 0x0 from a bare preset.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_right = WIDTH
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		_set_open(not visible)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	visible = open
	# The list needs the pointer; the game wants it back.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	var arena := get_parent() as Arena
	if arena == null:
		return
	var title := Label.new()
	title.text = "检查点（F2 关闭）"
	_list.add_child(title)
	var active: Checkpoint = arena.player.active_checkpoint if arena.player != null else null
	var points := arena.debug_checkpoints()
	for i in points.size():
		var checkpoint: Checkpoint = points[i]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s %2d  %s" % ["✓" if checkpoint == active else "   ", i + 1, Arena.checkpoint_label(checkpoint)]
		button.pressed.connect(func() -> void:
			_set_open(false)
			arena.debug_jump_to(checkpoint))
		_list.add_child(button)
	if points.is_empty():
		var none := Label.new()
		none.text = "这一关没有检查点"
		_list.add_child(none)
