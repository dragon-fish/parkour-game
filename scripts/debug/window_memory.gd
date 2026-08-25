extends Node

# Remembers the debug window's size and position across runs -- ✅ the owner:
# "能不能让引擎记住我运行debug时修改的窗口大小." Saves DEBOUNCED after every
# resize/move rather than at exit, because a debug run usually dies to the
# editor's stop button and never sees a close notification.
#
# A future settings menu supersedes this for players; for now it is the
# whole of the game's window preferences.
#
# OWNERSHIP RULE (drag memory vs the settings page, one cognition for window
# size): once user://window.cfg exists, IT wins the window-SIZE half of boot
# -- SettingsStore.apply_global() (scripts/ui/settings_store.gd) skips its own
# size application when this file is present, so a debug drag-resize is never
# silently overwritten by whatever settings.cfg has on file. Window MODE is
# untouched by this rule; this file never saves or restores it, and
# apply_global() always applies mode regardless. The settings page's 保存设置
# path (scripts/ui/settings_menu.gd's _on_save_pressed()) writes the chosen
# size into THIS file's "size" key too, so a deliberate settings choice
# updates the drag memory instead of losing to it on the next boot.

const PATH := "user://window.cfg"
const SAVE_DELAY := 0.5

var _save_timer: Timer

func _ready() -> void:
	# Headless has no window; the editor-embedded game has one it is not
	# allowed to touch ("Embedded window can't be resized").
	if DisplayServer.get_name() in ["headless", "embedded"]:
		return
	if get_window().get_flag(Window.FLAG_RESIZE_DISABLED):
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var size: Vector2i = cfg.get_value("window", "size", Vector2i.ZERO)
		var at: Vector2i = cfg.get_value("window", "position", Vector2i(-2147483648, 0))
		if size.x > 0 and size.y > 0:
			DisplayServer.window_set_size(size)
		if at.x != -2147483648:
			DisplayServer.window_set_position(at)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)
	get_viewport().size_changed.connect(_arm)

func _arm() -> void:
	_save_timer.start()

func _save() -> void:
	# Only a plain window's geometry is worth remembering -- a maximised or
	# fullscreen size restored as a floating window would be wrong twice.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("window", "size", DisplayServer.window_get_size())
	cfg.set_value("window", "position", DisplayServer.window_get_position())
	cfg.save(PATH)
