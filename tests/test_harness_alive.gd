extends ParkourTest

# The legacy suite is archived under tests/legacy/ (excluded from Godot's
# filesystem scan by tests/legacy/.gdignore). Without at least one live test
# under tests/, a passing run is indistinguishable from a broken runner --
# GUT reports zero failures and exits 0 whether it ran real tests or found
# none. This file is deliberately trivial and must keep at least these two
# tests as the suite's floor.

func test_the_runner_discovers_and_runs_a_live_test() -> void:
	assert_true(true, "the runner reached a live test method")

func test_the_physics_step_helper_still_advances_frames() -> void:
	var node := Node3D.new()
	get_tree().root.add_child(node)
	await step(1)
	assert_true(node.is_inside_tree(), "step() did not let a node enter the tree")
	node.queue_free()
	await step(1)
