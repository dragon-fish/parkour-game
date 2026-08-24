extends SceneTree

# Same idea as capture.gd, but reveals the tuning panel first so the captured
# frame actually shows it.

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var arena = packed.instantiate()
	# A capture run must never steal the pointer from whoever is using the
	# machine. Cleared BEFORE the scene enters the tree, not after: Arena
	# grabs the pointer in _ready(), and handing it back afterwards still
	# leaves the cursor yanked to the window centre for a frame -- which is
	# exactly what it feels like from the other side of the keyboard. See
	# Arena.capture_mouse, which the animation lab already turns off for the
	# same reason.
	if "capture_mouse" in arena:
		arena.capture_mouse = false
	root.add_child(arena)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for i in 30:
		await process_frame
	arena.get_node("TuningPanel").visible = true

	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport image was null")
		quit(1)
		return
	var error := image.save_png("res://.captures/p0_tuning_panel.png")
	print("capture err ", error)
	quit(0 if error == OK else 1)
