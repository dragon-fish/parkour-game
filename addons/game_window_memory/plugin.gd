@tool
extends EditorPlugin

# The EDITOR-side twin of scripts/debug/window_memory.gd: the embedded game's
# floating window is editor UI, so the game process cannot remember it, and
# the editor does not either -- ✅ the owner: "嵌入式确实可以拉大，但是godot
# 不会记住窗口大小." A half-second poll finds the "(DEBUG)" window when a run
# starts, applies the last saved rect once, and records any resize/move the
# owner makes afterwards.

const SAVE_PATH := "res://.godot/game_window_rect.cfg"

var _timer: Timer
var _window: Window = null
var _applied: bool = false
var _last_rect: Rect2i

func _enter_tree() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_scan)
	add_child(_timer)
	_timer.start()

func _exit_tree() -> void:
	_timer.queue_free()

func _scan() -> void:
	if _window != null and (not is_instance_valid(_window) or not _window.visible):
		_window = null
		_applied = false
	if _window == null:
		_window = _find_game_window()
		if _window == null:
			return
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			var size: Vector2i = cfg.get_value("rect", "size", Vector2i.ZERO)
			var at: Vector2i = cfg.get_value("rect", "position", Vector2i(-2147483648, 0))
			if size.x > 0 and size.y > 0:
				_window.size = size
			if at.x != -2147483648:
				_window.position = at
		_applied = true
		_last_rect = Rect2i(_window.position, _window.size)
		return
	var rect := Rect2i(_window.position, _window.size)
	if rect != _last_rect:
		_last_rect = rect
		var cfg := ConfigFile.new()
		cfg.set_value("rect", "size", rect.size)
		cfg.set_value("rect", "position", rect.position)
		cfg.save(SAVE_PATH)

func _find_game_window() -> Window:
	for node in EditorInterface.get_base_control().get_window().find_children(
			"*", "Window", true, false):
		var w := node as Window
		if w != null and w.visible and w.title.contains("(DEBUG)"):
			return w
	return null
