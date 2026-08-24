extends SceneTree

# Renders a bird's-eye view over every practice area (any Node3D child of the
# arena root whose name ends in "Area" — JumpArea, SlideArea, and whatever
# P2/P3 add), for visually spotting cross-area layout issues — e.g. one
# area's geometry sitting on top of another's — that a forward-facing
# spawn-camera screenshot (tools/capture.gd) would not reveal. The frame is
# computed from the live world AABB of every practice area's boxes, so it
# keeps fitting automatically as later phases add more areas.
#
# Run with (note: no --headless, a real rendering context is required):
#   .engine\Godot_v4.7.1-stable_win64_console.exe --path . --resolution 960x540 \
#       --script res://tools/capture_top_down.gd -- <scene_path> <output_png> [settle_frames]

func _initialize() -> void:
	_run()

func _collect_box_bodies(node: Node, out: Array) -> void:
	if node is StaticBody3D:
		var collision := node.get_node_or_null("Collision")
		if collision is CollisionShape3D and collision.shape is BoxShape3D:
			out.append(node)
	for child in node.get_children():
		_collect_box_bodies(child, out)

func _world_aabb(body: Node3D) -> AABB:
	var box: BoxShape3D = (body.get_node("Collision") as CollisionShape3D).shape
	var half := box.size * 0.5
	return body.global_transform * AABB(-half, box.size)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/main.tscn"
	var output := args[1] if args.size() > 1 else "res://capture_top_down.png"
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
	# Give the tree a frame before querying global transforms below —
	# is_inside_tree() is not reliably true for descendants on the very same
	# call that added their root to the tree.
	await process_frame

	# Union the world AABB of every box body across every practice area.
	var bounds: AABB
	var have_bounds := false
	for child in instance.get_children():
		if child is Node3D and String(child.name).ends_with("Area"):
			var boxes: Array = []
			_collect_box_bodies(child, boxes)
			for body in boxes:
				var aabb := _world_aabb(body)
				bounds = aabb if not have_bounds else bounds.merge(aabb)
				have_bounds = true

	if not have_bounds:
		bounds = AABB(Vector3(-10.0, 0.0, -10.0), Vector3(20.0, 1.0, 20.0))

	var center := bounds.get_center()
	var span: float = maxf(bounds.size.x, absf(bounds.size.z))

	var cam := Camera3D.new()
	cam.fov = 60.0
	# Mostly overhead with a slight offset for depth cues, framed wide enough
	# (span * 1.6) that the whole combined footprint fits regardless of how
	# many areas exist.
	var cam_pos := center + Vector3(0.0, span * 1.6, span * 0.35)
	cam.look_at_from_position(cam_pos, center, Vector3(0.0, 0.0, -1.0))
	root.add_child(cam)
	cam.current = true

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
		print("capture_top_down: %s -> %s (err %d)" % [scene_path, output, error])

	root.remove_child(instance)
	instance.free()
	quit(0 if error == OK else 1)
