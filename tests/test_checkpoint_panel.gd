extends ParkourTest

# F2 lists the level's checkpoints in their own order, ticks the active one,
# and a click respawns at the one clicked.

func _checkpoint(name: String, index: int, at: Vector3) -> Checkpoint:
	var checkpoint := Checkpoint.new()
	checkpoint.name = name
	checkpoint.index = index
	checkpoint.display_name = name
	checkpoint.position = at
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	checkpoint.add_child(shape)
	return checkpoint

func test_the_list_follows_the_level_order_and_a_click_jumps() -> void:
	var level: Arena = (load("res://templates/base_level.tscn") as PackedScene).instantiate()
	level.capture_mouse = false
	var later := _checkpoint("Later", 20, Vector3(0.0, 1.0, -30.0))
	var early := _checkpoint("Early", 10, Vector3(0.0, 1.0, -20.0))
	level.add_child(later)
	level.add_child(early)
	add_child_autofree(level)
	await step(5)
	var panel: CheckpointPanel = level.get_node("CheckpointPanel")
	level.player.active_checkpoint = later
	panel._set_open(true)
	await step(1)
	var buttons: Array = panel._list.get_children().filter(func(c): return c is Button)
	assert_eq(buttons.size(), 2, "not one row per checkpoint")
	assert_string_contains(buttons[0].text, "Early", "the list is not in the level's order")
	assert_false(buttons[0].text.begins_with("✓"), "an inactive checkpoint is ticked")
	assert_true(buttons[1].text.begins_with("✓"), "the active checkpoint is not ticked")
	buttons[0].pressed.emit()
	await step(2)
	assert_eq(level.player.active_checkpoint, early, "a click did not make that checkpoint active")
	assert_false(panel.visible, "the list stayed open after a jump")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
