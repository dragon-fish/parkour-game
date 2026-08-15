extends SceneTree

# Renders a scene off the main game loop and writes a PNG, so visual checks do
# not need a human at the keyboard.
#
# Run with (note: no --headless, a real rendering context is required):
#   .engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 \
#       --script res://tools/capture.gd -- <scene_path> <output_png> [settle_frames]

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/main.tscn"
	var output := args[1] if args.size() > 1 else "res://capture.png"
	var settle := int(args[2]) if args.size() > 2 else 90

	var packed: PackedScene = load(scene_path)
	var instance = packed.instantiate()
	root.add_child(instance)

	# The arena grabs the mouse in _ready(); give it straight back so a capture
	# run never steals the pointer from whoever is using the machine.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for i in settle:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport image was null")
		quit(1)
		return
	var error := image.save_png(output)
	print("capture: %s -> %s (err %d)" % [scene_path, output, error])
	quit(0 if error == OK else 1)
