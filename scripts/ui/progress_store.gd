class_name ProgressStore
extends RefCounted

# What the player has already been through. Same static, stateless shape as
# SettingsStore (scripts/ui/settings_store.gd) and it lives beside it for
# that reason -- this class is never instantiated.
#
# A KEY MISSING FROM defaults() IS SILENTLY DROPPED by load_progress(), which
# only copies keys it already knows about. Add the key here first, always.

## Injectable rather than a const, for the same reason SettingsStore.path is:
## a test points this at its own file so the suite never reads, writes or
## deletes the player's real progress.
static var path := "user://progress.cfg"

const _SECTION := "progress"

## True when the next visit to the front door goes straight into the tutorial
## instead of opening the menu.
##
## PER SESSION AND NEVER WRITTEN TO DISK. The settings row that sets it is a
## request to play the tutorial now; persisted, it would send the player back
## into the tutorial on every launch with no way out.
static var replay_requested: bool = false

## The full progress blob with every key at its shipped default.
static func defaults() -> Dictionary:
	return {
		tutorial_finished = false,
	}

## Reads the blob from disk, merging in defaults() for any key the file is
## missing -- including "no file at all", which is every first launch.
static func load_progress() -> Dictionary:
	var progress := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return progress
	for key in progress:
		progress[key] = cfg.get_value(_SECTION, key, progress[key])
	return progress

static func save_progress(progress: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in progress:
		cfg.set_value(_SECTION, key, progress[key])
	cfg.save(path)

## The one question the pause menu, the front door and the tutorial level all
## ask, answered in one place.
static func tutorial_finished() -> bool:
	return bool(load_progress().get("tutorial_finished", false))

## Records the tutorial as finished, keeping every other key already on disk.
static func mark_tutorial_finished() -> void:
	var progress := load_progress()
	progress.tutorial_finished = true
	save_progress(progress)
