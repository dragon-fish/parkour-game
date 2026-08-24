class_name DebugToggles
extends RefCounted

# On-disk model for which debug overlays (capsule, scripted path, shimmy
# probes, clip offset tuner) were left on, across sessions. Headless and
# UI-free by design, same spirit as CameraRig.load_preferences() -- so it is
# testable without building the tuning panel, and applying it must not run in
# headless tests that never build that panel either.

const DEFAULT_PATH := "user://debug_toggles.cfg"
const SECTION := "overlays"

## Overlay name -> whether it was on. Empty when the file does not exist yet
## (every first run), not an error.
static func load_states(path: String = DEFAULT_PATH) -> Dictionary:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return {}
	var states := {}
	for key in file.get_section_keys(SECTION):
		states[key] = bool(file.get_value(SECTION, key, false))
	return states

static func save_states(states: Dictionary, path: String = DEFAULT_PATH) -> void:
	var file := ConfigFile.new()
	for overlay_name in states:
		file.set_value(SECTION, overlay_name, bool(states[overlay_name]))
	file.save(path)
