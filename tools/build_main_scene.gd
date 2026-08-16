extends SceneTree

# Generates scenes/main.tscn: the graybox arena. The actual node tree is built
# by ArenaBuilder (tools/arena_builder.gd) -- kept out of this file so
# tests/test_arena.gd can call the exact same builder directly and compare its
# in-memory output against what gets committed here, instead of the two ever
# being able to silently drift apart.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_main_scene.gd

const OUTPUT := "res://scenes/main.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	var root: Node3D = ArenaBuilder.new().build()

	DirAccess.make_dir_recursive_absolute("res://scenes")
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)
