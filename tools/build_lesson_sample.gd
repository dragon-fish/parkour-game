extends SceneTree

# Generates scenes/levels/lessons/sample_wall.tscn: the smallest thing that
# proves the lesson loop runs end to end.
#
# NOT A TEMPLATE FOR REAL LESSONS. A real lesson inherits
# templates/base_level.tscn so its author can open it and run around in it
# while shaping the geometry (see docs/level-templates.md and the spec's
# 「每一课都是一个能单独打开游玩的关卡」). An inherited scene cannot be built
# from code -- inheritance is an editor concept -- so this sample carries only
# a root and a Content node, and cannot be played on its own.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_lesson_sample.gd

const OUTPUT := "res://scenes/levels/lessons/sample_wall.tscn"

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "SampleWall"

	var content := Node3D.new()
	content.name = "Content"
	root.add_child(content)

	# A waist-high wall: high enough to want vaulting, low enough that failing
	# to costs nothing.
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.position = Vector3(0.0, 0.5, 0.0)
	var size := Vector3(6.0, 1.0, 0.6)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.60, 0.68)
	# Growth and collapse are alpha for now, so the material has to be able to
	# express transparency at all.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	mesh_instance.mesh = mesh
	wall.add_child(mesh_instance)

	content.add_child(wall)

	for node in [content, wall, shape, mesh_instance]:
		node.owner = root

	DirAccess.make_dir_recursive_absolute("res://scenes/levels/lessons")
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
