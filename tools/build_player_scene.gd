extends SceneTree

# Generates scenes/player/player.tscn. Scenes are built in code rather than by
# hand so the whole project is reproducible without an editor session.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_player_scene.gd
#
# One-shot scaffolding: once the .tscn exists it is the source of truth, and
# re-running this would discard any later edits made in the editor.

const OUTPUT := "res://scenes/player/player.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/player/player.gd"))

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	shape.shape = capsule
	player.add_child(shape)
	shape.owner = player

	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(load("res://scripts/camera/camera_rig.gd"))
	# Eye height: 0.7 above the capsule centre puts the view near the top of a
	# 1.8 m body without clipping through the collision shape.
	rig.position = Vector3(0.0, 0.7, 0.0)
	player.add_child(rig)
	rig.owner = player

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	cam.owner = player

	# Reserved for the P5 procedural first-person body. Empty for now, but
	# present so adding a skeleton later does not restructure the scene.
	var body_root := Node3D.new()
	body_root.name = "BodyRoot"
	player.add_child(body_root)
	body_root.owner = player

	player.camera_rig = rig

	DirAccess.make_dir_recursive_absolute("res://scenes/player")
	var packed := PackedScene.new()
	var pack_error := packed.pack(player)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
