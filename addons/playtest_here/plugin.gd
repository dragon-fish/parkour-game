@tool
extends EditorPlugin

# "Play from here": run the scene being edited, with the body dropped at the
# editor viewport's own camera.
#
# A SCENE THAT ALREADY HAS A PLAYER RUNS AS ITSELF. Anything else -- a
# geometry .scn, a prop, a blockout with nothing but meshes -- is instanced
# into a copy of templates/base_level.tscn, which is where the player, the
# sun, the HUD and the safety net already live. Nothing is written into the
# scene being tested, and the shell is scratch (SHELL, gitignored).
#
# Where to stand is left in a file for the run to pick up
# (scripts/debug/playtest_spawn.gd): the scene may be unsaved, and a scene
# with its own player must not be rewritten just to move a spawn.

const BASE_LEVEL := "res://templates/base_level.tscn"
const SHELL := "res://addons/playtest_here/_scratch_playtest.tscn"
const NOTE := "user://playtest_here.cfg"

var _button: Button


func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "从这里试跑"
	_button.tooltip_text = "在编辑器视口相机所在位置开始游玩当前场景（自动 noclip）"
	_button.pressed.connect(_play_here)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _button)


func _exit_tree() -> void:
	if _button != null:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _button)
		_button.queue_free()
		_button = null


func _play_here() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null:
		push_warning("[playtest] no scene open")
		return
	var camera := _viewport_camera()
	if camera == null:
		push_warning("[playtest] no 3D viewport to take a position from")
		return
	_leave_note(camera.global_position, camera.global_rotation.y)
	if _has_player(scene):
		if scene.scene_file_path.is_empty():
			push_warning("[playtest] save the scene first; an unsaved scene cannot be run")
			return
		EditorInterface.play_custom_scene(scene.scene_file_path)
		return
	var shell := _build_shell(scene)
	if shell.is_empty():
		return
	EditorInterface.play_custom_scene(shell)


## The 3D editor viewport's camera. Four viewports exist; the one the mouse
## last worked in is not exposed, so this takes the first that has a camera.
func _viewport_camera() -> Camera3D:
	for i in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(i)
		if viewport != null and viewport.get_camera_3d() != null:
			return viewport.get_camera_3d()
	return null


func _leave_note(position: Vector3, yaw: float) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("at", "position", position)
	cfg.set_value("at", "yaw", yaw)
	cfg.set_value("at", "unix_time", Time.get_unix_time_from_system())
	cfg.save(NOTE)


static func _has_player(scene: Node) -> bool:
	if scene is Player:
		return true
	for node in scene.find_children("*", "CharacterBody3D", true, false):
		if node is Player:
			return true
	return false


## base_level with the scene under test instanced into it, saved as scratch.
## Returns the path, or "" when it could not be built.
func _build_shell(scene: Node) -> String:
	var path := scene.scene_file_path
	if path.is_empty():
		push_warning("[playtest] save the scene first; an unsaved scene cannot be instanced")
		return ""
	var base := (load(BASE_LEVEL) as PackedScene).instantiate()
	var under_test := (load(path) as PackedScene).instantiate()
	under_test.name = "UnderTest"
	base.add_child(under_test)
	under_test.owner = base
	var packed := PackedScene.new()
	if packed.pack(base) != OK:
		base.free()
		push_warning("[playtest] could not pack the shell")
		return ""
	base.free()
	if ResourceSaver.save(packed, SHELL) != OK:
		push_warning("[playtest] could not save the shell to %s" % SHELL)
		return ""
	return SHELL
