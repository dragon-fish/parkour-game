extends SceneTree

# Renders a scene off the main game loop and writes a PNG, so visual checks do
# not need a human at the keyboard.
#
# Run with (note: no --headless, a real rendering context is required):
#   .engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 \
#       --quit-after 300 --script res://tools/capture.gd -- <scene_path> <output_png> [settle_frames]
#
# --quit-after <N> is a hard backstop, not the normal exit path: this script
# always calls quit() itself once the PNG is written. It forces the engine to
# terminate after N frames regardless, in case a windowed run somehow doesn't
# exit on its own — pick N comfortably above the settle_frames you pass plus
# a small margin.

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/main.tscn"
	var output := args[1] if args.size() > 1 else "res://capture.png"
	var settle := int(args[2]) if args.size() > 2 else 90

	var packed: PackedScene = load(scene_path)
	var instance = packed.instantiate()
	# A capture run must never steal the pointer from whoever is using the
	# machine. Cleared BEFORE the scene enters the tree, not after: Arena
	# grabs the pointer in _ready(), and handing it back afterwards still
	# leaves the cursor yanked to the window centre for a frame -- which is
	# exactly what it feels like from the other side of the keyboard. See
	# Arena.capture_mouse, which the animation lab already turns off for the
	# same reason.
	if "capture_mouse" in instance:
		instance.capture_mouse = false
	root.add_child(instance)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for i in settle:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var error := OK
	if image == null:
		push_error("viewport image was null")
		error = FAILED
	else:
		error = image.save_png(output)
		print("capture: %s -> %s (err %d)" % [scene_path, output, error])

	# Free the instantiated scene before quitting. Leaving it live in the
	# tree at shutdown means quit() has to tear down a whole running scene
	# (player physics, camera, viewport texture) with a real rendering
	# context attached — the plausible cause of a windowed process
	# surviving quit() instead of exiting cleanly.
	root.remove_child(instance)
	instance.free()

	quit(0 if error == OK else 1)
