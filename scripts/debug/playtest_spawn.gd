extends Node

# The runtime half of "play from here" (addons/playtest_here): the editor
# leaves a note saying where its viewport was looking, and whatever scene
# starts next puts the body there.
#
# A NOTE ON DISK, not a scene edit. The scene being tested may be one the
# editor is holding unsaved, or one with a player already in it that nothing
# should rewrite; a file beside the project is the one channel that works for
# both and leaves nothing behind. It is deleted as it is read, so a normal run
# afterwards starts where the level says.
#
# NOCLIP IS ON ARRIVAL. The point of dropping in mid-air over a rooftop is to
# look at the rooftop, and a body that falls to its death on arrival has
# answered a question nobody asked. Press T to turn it off and play properly.

const NOTE := "user://playtest_here.cfg"
## Past this the note is stale -- the editor wrote it for a run that never
## happened, and a later ordinary run must not be hijacked by it.
const FRESH_FOR_SECONDS := 120.0


func _ready() -> void:
	if not FileAccess.file_exists(NOTE):
		return
	var cfg := ConfigFile.new()
	if cfg.load(NOTE) != OK:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NOTE))
	var written: float = float(cfg.get_value("at", "unix_time", 0.0))
	if absf(Time.get_unix_time_from_system() - written) > FRESH_FOR_SECONDS:
		return
	var position: Vector3 = cfg.get_value("at", "position", Vector3.ZERO)
	var yaw: float = float(cfg.get_value("at", "yaw", 0.0))
	_place.call_deferred(position, yaw)


func _place(position: Vector3, yaw: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		await get_tree().process_frame
		scene = get_tree().current_scene
	# AFTER the level has placed the body itself: Arena moves the player to its
	# spawn during load, and arriving before that means being moved away again.
	if scene is Arena and not (scene as Arena).is_level_ready:
		await (scene as Arena).level_ready
	await get_tree().physics_frame
	var player := _player_in(scene)
	if player == null:
		# The scene need not be the level: a shell instances the level under
		# test, and a test world hangs its player elsewhere entirely.
		player = _player_in(get_tree().root)
	if player == null:
		push_warning("[playtest] no player in %s to place" % scene)
		return
	player.global_position = position
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	if "noclip" in player and not player.noclip:
		player.toggle_noclip()
	if player.fall_tracker != null:
		player.fall_tracker.reset(position.y)


static func _player_in(scene: Node) -> Player:
	if scene == null:
		return null
	if scene is Player:
		return scene
	for node in scene.find_children("*", "CharacterBody3D", true, false):
		if node is Player:
			return node
	return null
