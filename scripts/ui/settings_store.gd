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

const PATH := "user://settings.cfg"

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
	if cfg.load(PATH) != OK:
		return s
	for key in s:
		s[key] = cfg.get_value(_SECTION, key, s[key])
	return s


## Writes the settings blob to disk, one key per ConfigFile value.
static func save_settings(s: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in s:
		cfg.set_value(_SECTION, key, s[key])
	cfg.save(PATH)


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
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(s.window_size)


## Applies the per-player half of the settings: camera sensitivity and FOV
## onto a live MovementConfig (e.g. from Player setup).
static func apply_to_config(s: Dictionary, config: MovementConfig) -> void:
	config.camera.mouse_sensitivity = s.sensitivity
	config.camera.fov_base = s.fov
