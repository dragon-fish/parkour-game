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

## antialiasing option -> Viewport.msaa_3d. "fxaa" is absent on purpose: it is
## a post-process pass, applied through screen_space_aa instead.
const MSAA_MODES := {
	"msaa_2x": Viewport.MSAA_2X,
	"msaa_4x": Viewport.MSAA_4X,
}

## What "0%" sets the bus to. -inf is what linear_to_db(0) returns and the
## bus rejects it; -80 dB is inaudible and reversible.
const MUTED_DB := -80.0

## CameraConfig.third_person_body_scale with small_third_person_body on.
## Judged by eye in sp01b's interiors: 0.75 read best but lost too many hands,
## 0.85 kept most of both.
const SMALL_THIRD_PERSON_BODY_SCALE := 0.85


## The full settings blob with every key at its shipped default.
static func defaults() -> Dictionary:
	return {
		window_mode = "windowed",
		window_size = Vector2i(1440, 810),
		sensitivity = 0.0022,
		fov = 90.0,
		# 0..1, the AMPLITUDE the player asked for -- not decibels: nobody
		# thinks in dB. The conversion to dB happens on
		# the way to the bus, in apply_global(), because that curve is the
		# whole point: a slider that changes dB linearly spends most of its
		# travel in a range nobody can hear apart.
		volume = 0.8,
		# NOT off by default. The character's outline is a one-millimetre
		# inverted hull (shaders/matcap_outline.gdshader), which is a sub-pixel
		# edge at any normal viewing distance and crawls without multisampling.
		antialiasing = "msaa_2x",
		# Off: the moves' hand positions are measured against a full-size body.
		small_third_person_body = false,
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
	# A file written before volume was a percentage carries volume_db. Read
	# it once, on its own terms, so an upgrade does not silently reset the
	# volume to the default.
	if cfg.has_section_key(_SECTION, "volume_db") and not cfg.has_section_key(_SECTION, "volume"):
		s.volume = clampf(db_to_linear(float(cfg.get_value(_SECTION, "volume_db", 0.0))), 0.0, 1.0)
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
	# linear_to_db is the standard mapping, and Godot's own recommendation
	# for a volume slider: perceived loudness follows the logarithm, so an
	# amplitude of 0.5 is -6 dB rather than "half". Silence is a special
	# case -- linear_to_db(0) is -inf, which the bus will not take.
	var amplitude: float = clampf(float(s.volume), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(amplitude) if amplitude > 0.0 else MUTED_DB)

	# MSAA is the setting that matters for the character: its outline is real
	# geometry, which multisampling resolves and a post-process pass can only
	# blur. FXAA stays on the list for machines that cannot spare the samples.
	# Applied before the display guards below because it touches no
	# DisplayServer and is harmless under headless.
	var viewport: Viewport = (Engine.get_main_loop() as SceneTree).root
	viewport.msaa_3d = MSAA_MODES.get(s.antialiasing, Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA 			if s.antialiasing == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED

	# Headless has no window; the editor-embedded game has one it is not
	# allowed to touch ("Embedded window can't be resized"). Same guard as
	# scripts/debug/window_memory.gd.
	if DisplayServer.get_name() in ["headless", "embedded"]:
		return
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	if root.get_flag(Window.FLAG_RESIZE_DISABLED):
		return

	# Three modes, and Godot's own naming is the confusing part: its
	# WINDOW_MODE_FULLSCREEN is already a BORDERLESS fullscreen (the
	# alt-tab-friendly one); EXCLUSIVE_FULLSCREEN is the one that takes the
	# display over. "borderless" here is the third thing people mean by the
	# word: a windowed window with its frame off.
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	if s.window_mode == "fullscreen":
		mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,
		s.window_mode == "borderless")

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
	# _on_save_pressed(): a deliberate Save Settings click writes its size into
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
	config.camera.third_person_body_scale = SMALL_THIRD_PERSON_BODY_SCALE if s.small_third_person_body else 1.0
