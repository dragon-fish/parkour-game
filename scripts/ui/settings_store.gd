class_name SettingsStore
extends RefCounted

# Pure-logic settings blob for the main menu: defaults, disk round-trip, and
# applying the blob to the two places it actually matters. Every member here
# is static and stateless, same shape as MeTheme -- this class is never
# instantiated.
#
# SPLIT IN TWO ON PURPOSE, against the original brief's single apply(). At
# boot (main menu) there is no Player yet, so no MovementConfig is reachable
# -- only the window/audio half can be applied. Camera fields live on each
# player's own MovementConfig and only exist once a Player does. So:
#   - apply_global(): window + audio, engine-wide, callable with no Player.
#   - apply_to_config(): camera fields, callable once a MovementConfig exists.
# Callers (PauseUi at boot, Player setup) are later tasks, not this one.

## Injectable rather than a const: tests/test_menu.gd points this at
## user://settings_test.cfg for the whole file's run (before_all/after_all)
## so the suite never reads, writes, or deletes the author's real settings.
static var path := "user://settings.cfg"

const _SECTION := "settings"


## The full settings blob with every key at its shipped default.
static func defaults() -> Dictionary:
	return {
		window_mode = "windowed",
		window_size = Vector2i(1440, 810),
		sensitivity = 0.0022,
		fov = 90.0,
		volume_db = 0.0,
	}


## Loads the settings blob from disk, merging in defaults() for any key
## missing from the file (including "no file at all", i.e. first run).
static func load_settings() -> Dictionary:
	var s := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	for key in s:
		s[key] = cfg.get_value(_SECTION, key, s[key])
	return s


## Writes the settings blob to disk, one key per ConfigFile value.
static func save_settings(s: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in s:
		cfg.set_value(_SECTION, key, s[key])
	cfg.save(path)


## Applies the engine-wide half of the settings: window mode/size and the
## master audio bus. Callable with no Player in the scene, e.g. at boot.
static func apply_global(s: Dictionary) -> void:
	AudioServer.set_bus_volume_db(0, s.volume_db)

	# Headless has no window; the editor-embedded game has one it is not
	# allowed to touch ("Embedded window can't be resized"). Same guard as
	# scripts/debug/window_memory.gd.
	if DisplayServer.get_name() in ["headless", "embedded"]:
		return
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	if root.get_flag(Window.FLAG_RESIZE_DISABLED):
		return

	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if s.window_mode == "fullscreen" else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	# OWNERSHIP RULE (drag memory vs settings page, one cognition for window
	# size): WindowMemory (scripts/debug/window_memory.gd) and this settings
	# page's window_size row both claim to know "the" window size, so boot
	# has to pick one winner or the two fight every launch. Once
	# user://window.cfg exists, the drag memory wins at boot -- the SIZE half
	# of this call is skipped entirely, deliberately not just overwritten
	# with the same value, so a debug resize the player just made is never
	# clobbered back to whatever settings.cfg happened to have on file. Mode
	# has no such conflict (WindowMemory never saves or restores mode) and
	# always applies above, unconditionally.
	#
	# The other half of this rule lives in settings_menu.gd's
	# _on_save_pressed(): a deliberate 保存设置 choice writes its size into
	# user://window.cfg too (same "size" key WindowMemory owns), so choosing
	# a size on the settings page updates the drag memory instead of losing
	# to it on the next boot.
	if mode == DisplayServer.WINDOW_MODE_WINDOWED and not FileAccess.file_exists(WindowMemory.PATH):
		DisplayServer.window_set_size(s.window_size)


## Applies the per-player half of the settings: camera sensitivity and FOV
## onto a live MovementConfig (e.g. from Player setup).
static func apply_to_config(s: Dictionary, config: MovementConfig) -> void:
	config.camera.mouse_sensitivity = s.sensitivity
	config.camera.fov_base = s.fov
