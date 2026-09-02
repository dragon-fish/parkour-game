extends ParkourTest

# The TIMING contract, which is all that is asserted. What growth LOOKS like
# is alpha today and a shader later, and neither is tested: the point of
# separating them is that the look can change without touching this.

var _solid: GrowingSolid

func after_each() -> void:
	if is_instance_valid(_solid):
		_solid.queue_free()
	_solid = null

func _growing(seconds: float) -> GrowingSolid:
	_solid = GrowingSolid.new()
	_solid.grow_time = seconds
	add_child_autofree(_solid)
	await step(1)
	return _solid

func test_growth_passes_through_the_middle_instead_of_snapping() -> void:
	# The show may be crude -- it is alpha today and a dissolve shader later --
	# but it must take the time it says it takes. A snap would mean the timing
	# contract has quietly stopped holding.
	var solid: GrowingSolid = await _growing(1.0)
	solid.begin()
	await step(10)
	assert_gt(solid.progress, 0.0, "growth never started")
	assert_lt(solid.progress, 1.0, "growth finished instantly instead of taking grow_time")

func test_growth_announces_itself_once() -> void:
	var solid: GrowingSolid = await _growing(0.1)
	# A bare int captured by a lambda is copied by value in GDScript and
	# never reflects back into this scope -- use a one-cell Array, this
	# project's established idiom for a signal-count closure.
	var grown: Array = [0]
	solid.grown.connect(func() -> void: grown[0] += 1)
	solid.begin()
	await step(30)
	assert_eq(grown[0], 1, "growth announced itself %d times" % grown[0])

func test_beginning_locks_the_obstacle_it_belongs_to() -> void:
	# Growth starting IS the moment the anchor is pinned -- see
	# TutorialObstacle's own note on why the lock is not negotiable.
	var solid: GrowingSolid = await _growing(0.5)
	var obstacle := TutorialObstacle.new()
	add_child_autofree(obstacle)
	solid.obstacle = obstacle
	assert_false(obstacle.locked, "test setup: it was locked before growth began")
	solid.begin()
	await step(1)
	assert_true(obstacle.locked, "growth began without pinning the anchor")

func test_a_block_with_a_swarm_drives_the_swarm_rather_than_its_alpha() -> void:
	# The wiring bug this catches: a CubeSwarm IS a GeometryInstance3D, so an
	# unfiltered find_children() sweeps it into the fade list. The block then
	# fades out with all its cubes standing still -- the exact effect the
	# swarm exists to replace, and no error anywhere.
	var solid := GrowingSolid.new()
	solid.grow_time = 1.0
	var swarm := CubeSwarm.new()
	swarm.box_size = Vector3.ONE
	swarm.cube_size = 0.5
	solid.add_child(swarm)
	add_child_autofree(solid)
	await step(1)
	assert_almost_eq(swarm.progress, 1.0, 0.01,
		"a block that has not grown yet is not fully dispersed")
	assert_almost_eq(swarm.transparency, 0.0, 0.01,
		"the swarm was faded instead of dispersed")

func test_a_block_with_no_swarm_still_fades() -> void:
	# The fallback must keep working: not everything in this game is a box,
	# and a lesson without a swarm may not simply stop appearing.
	var solid := GrowingSolid.new()
	solid.grow_time = 1.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	solid.add_child(mesh)
	add_child_autofree(solid)
	await step(1)
	assert_almost_eq(mesh.transparency, 1.0, 0.01,
		"a block with no swarm is visible before it has grown")
