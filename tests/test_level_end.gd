extends ParkourTest

# Touching the chapter's end goes back to the main menu, once.

const WALKER := """
extends CharacterBody3D
func touch_checkpoint(_c) -> void:
	pass
"""

var _nodes: Array[Node] = []
var _requested: Array[String] = []

func before_each() -> void:
	_requested.clear()
	PauseUi._change_scene = func(path: String) -> void: _requested.append(path)

func after_each() -> void:
	PauseUi._change_scene = Callable(PauseUi, "_real_change_scene")
	PauseUi._pending_scene_change = false
	get_tree().paused = false
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await step(1)

func _body(script_source: String, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	if script_source != "":
		var script := GDScript.new()
		script.source_code = script_source
		script.reload()
		body.set_script(script)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	body.add_child(shape)
	body.position = at
	get_tree().root.add_child(body)
	_nodes.append(body)
	return body

func _end() -> LevelEnd:
	var area := LevelEnd.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	area.add_child(shape)
	get_tree().root.add_child(area)
	_nodes.append(area)
	return area

func test_the_player_reaching_the_end_goes_to_the_menu_once() -> void:
	_end()
	var body := _body(WALKER, Vector3(10.0, 0.0, 0.0))
	await step(2)
	body.global_position = Vector3.ZERO
	await step(4)
	body.global_position = Vector3(10.0, 0.0, 0.0)
	await step(4)
	body.global_position = Vector3.ZERO
	await step(4)
	assert_eq(_requested.size(), 1, "the end asked for the menu %d times" % _requested.size())

func test_something_else_touching_the_end_does_nothing() -> void:
	_end()
	var body := _body("", Vector3(10.0, 0.0, 0.0))
	await step(2)
	body.global_position = Vector3.ZERO
	await step(4)
	assert_eq(_requested.size(), 0, "a body that is not the player ended the level")
