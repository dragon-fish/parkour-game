extends ParkourTest

# The rule deciding where a drawn node lands in the tree. Real nodes, no
# editor -- which is the reason this rule does not live in the plugin script.

const Placement := preload("res://addons/blockout_tools/placement.gd")

var _root: Node3D

func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)

func test_a_collision_shape_goes_inside_what_can_hold_it() -> void:
	var area := Area3D.new()
	_root.add_child(area)
	assert_eq(Placement.parent_for(area, _root, true), area, \
		"a shape drawn on an Area3D did not become its child")

func test_a_collision_shape_on_something_that_cannot_hold_one_is_a_sibling() -> void:
	var branch := Node3D.new()
	_root.add_child(branch)
	var plain := Node3D.new()
	branch.add_child(plain)
	assert_eq(Placement.parent_for(plain, _root, true), branch, \
		"a shape drawn on a plain Node3D did not land beside it")

func test_geometry_is_always_a_sibling_even_on_an_area() -> void:
	# Only collision shapes go inside a volume. A CSG solid drawn while one
	# happens to be selected is still geometry, not part of the trigger.
	var area := Area3D.new()
	_root.add_child(area)
	assert_eq(Placement.parent_for(area, _root, false), _root, \
		"a solid was buried inside the selected Area3D")

func test_the_scene_root_takes_its_own_children() -> void:
	# The root has no parent to be a sibling of.
	assert_eq(Placement.parent_for(_root, _root, false), _root)
	assert_eq(Placement.parent_for(null, _root, false), _root)

func test_a_sibling_lands_directly_after_the_node_it_joined() -> void:
	var first := Node3D.new()
	var second := Node3D.new()
	var third := Node3D.new()
	_root.add_child(first)
	_root.add_child(second)
	_root.add_child(third)
	assert_eq(Placement.insert_index(_root, first), 1, \
		"the new node would have been left at the end of the list")
	assert_eq(Placement.insert_index(_root, third), 3)

func test_nothing_to_sit_after_leaves_the_order_alone() -> void:
	var stranger := Node3D.new()
	add_child_autofree(stranger)
	assert_eq(Placement.insert_index(_root, stranger), -1, \
		"a node from another branch was treated as a sibling")
	assert_eq(Placement.insert_index(_root, null), -1)
