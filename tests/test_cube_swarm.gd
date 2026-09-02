extends ParkourTest

# The swarm's PLACEMENT, which is the half that lives on the CPU. What it
# looks like leaving -- how far, how bright, how fast -- is the author's to
# judge and is asserted nowhere.

var _swarm: CubeSwarm

func after_each() -> void:
	if is_instance_valid(_swarm):
		_swarm.queue_free()
	_swarm = null

func _swarm_of(size: Vector3, cube: float) -> CubeSwarm:
	var swarm := CubeSwarm.new()
	swarm.box_size = size
	swarm.cube_size = cube
	add_child_autofree(swarm)
	await step(1)
	_swarm = swarm
	return swarm

func test_the_grid_fills_the_box_it_stands_in_for() -> void:
	# A wrong grid derivation is silent and total: one cube where a wall
	# should be, or a hundred thousand where two hundred belong.
	var swarm: CubeSwarm = await _swarm_of(Vector3(6.0, 1.0, 0.5), 0.25)
	assert_eq(swarm.grid_counts(), Vector3i(24, 4, 2),
		"the grid does not divide the box by cube_size")
	assert_eq(swarm.multimesh.instance_count, 24 * 4 * 2,
		"the multimesh holds a different number of cubes than the grid says")

func test_the_swarm_material_finds_its_shader() -> void:
	# The path is a string. A wrong one loads nothing and the swarm renders as
	# untouched grey boxes that never move.
	var swarm: CubeSwarm = await _swarm_of(Vector3.ONE, 0.5)
	var material := (swarm.multimesh.mesh as BoxMesh).material as ShaderMaterial
	assert_not_null(material, "the swarm's mesh carries no ShaderMaterial")
	assert_not_null(material.shader, "the swarm's material has no shader resource")

func test_a_packed_swarm_sits_inside_the_box() -> void:
	# Off-by-one centring puts the swarm half a box away from the collision it
	# stands in for, so the block you see is not the block you hit.
	var swarm: CubeSwarm = await _swarm_of(Vector3(2.0, 1.0, 1.0), 0.25)
	var half: Vector3 = swarm.box_size * 0.5
	for i in swarm.multimesh.instance_count:
		var origin: Vector3 = swarm.cube_origin(i, 0.0)
		assert_true(absf(origin.x) <= half.x + 0.001 \
			and absf(origin.y) <= half.y + 0.001 \
			and absf(origin.z) <= half.z + 0.001,
			"cube %d starts outside the box it fills: %s" % [i, origin])

func test_a_finished_swarm_has_left_the_box() -> void:
	# A zero or degenerate direction makes the block collapse in place instead
	# of dispersing -- it just shrinks and winks out, which is the fade this
	# class exists to replace.
	var swarm: CubeSwarm = await _swarm_of(Vector3(2.0, 1.0, 1.0), 0.25)
	var half: Vector3 = swarm.box_size * 0.5
	for i in swarm.multimesh.instance_count:
		var origin: Vector3 = swarm.cube_origin(i, 1.0)
		assert_true(absf(origin.x) > half.x or absf(origin.y) > half.y \
			or absf(origin.z) > half.z,
			"cube %d never left the box: %s" % [i, origin])
