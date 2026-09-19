extends ParkourTest

# A pane stops a body that walks into it and breaks for one that runs into it,
# letting the run carry through; a respawn puts it back.

const RUNNER := """
extends CharacterBody3D
var speed := 0.0
func touch_checkpoint(_c) -> void:
	pass
func _physics_process(_delta: float) -> void:
	velocity = Vector3(0.0, 0.0, -speed)
	move_and_slide()
"""

var _nodes: Array[Node] = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await step(1)

## A 1.2 x 2 m pane standing across -Z at z = -2, and a body at the origin
## heading at it at `speed`. Returns [glass, body].
func _scene(speed: float) -> Array:
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	_nodes.append(holder)
	var pane := AnimatableBody3D.new()
	pane.name = "Pane"
	pane.position = Vector3(0.0, 1.0, -2.0)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 2.0, 0.02)
	mesh.mesh = box
	pane.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	pane.add_child(collision)
	holder.add_child(pane)
	var glass := BreakableGlass.new()
	glass.name = "Glass"
	glass.pane = NodePath("../Pane")
	var reach := Area3D.new()
	reach.name = "Reach"
	reach.position = pane.position
	var reach_shape := CollisionShape3D.new()
	var reach_box := BoxShape3D.new()
	reach_box.size = box.size + Vector3.ONE * 1.2
	reach_shape.shape = reach_box
	reach.add_child(reach_shape)
	glass.add_child(reach)
	holder.add_child(glass)
	var script := GDScript.new()
	script.source_code = RUNNER
	script.reload()
	var body := CharacterBody3D.new()
	body.set_script(script)
	var capsule := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	capsule.shape = cap
	body.add_child(capsule)
	body.position = Vector3(0.0, 0.9, 0.0)
	body.set("speed", speed)
	holder.add_child(body)
	return [glass, body]

func test_a_walk_into_the_pane_is_stopped() -> void:
	var parts := _scene(1.5)
	await step(120)
	var glass: BreakableGlass = parts[0]
	var body: CharacterBody3D = parts[1]
	assert_false(glass.is_broken(), "a walking pace broke the pane")
	assert_gt(body.position.z, -2.0, "the walking body passed through an unbroken pane")

func test_a_run_into_the_pane_breaks_it_and_carries_through() -> void:
	var parts := _scene(6.0)
	await step(60)
	var glass: BreakableGlass = parts[0]
	var body: CharacterBody3D = parts[1]
	assert_true(glass.is_broken(), "a run did not break the pane")
	assert_lt(body.position.z, -3.0, "the run stopped at the pane instead of carrying through")

func test_a_respawn_puts_the_pane_back() -> void:
	var parts := _scene(6.0)
	await step(60)
	var glass: BreakableGlass = parts[0]
	glass.reset_for_respawn()
	assert_false(glass.is_broken(), "a respawn left the pane broken")
	var pane := glass.get_node(glass.pane) as Node3D
	assert_true((pane.get_node("Mesh") as MeshInstance3D).visible, "a respawn left the pane invisible")
	for child in pane.get_children():
		if child is CollisionShape3D:
			assert_false((child as CollisionShape3D).disabled, "a respawn left the pane without collision")
