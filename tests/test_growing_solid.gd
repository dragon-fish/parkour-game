extends ParkourTest

# The TIMING contract, which is all that is asserted. What growth LOOKS like
# is alpha today and a shader later, and neither is tested: the point of
# separating them is that the look can change without touching this.

var _solid: GrowingSolid
var _body: StaticBody3D

func after_each() -> void:
	if is_instance_valid(_solid):
		_solid.queue_free()
	_solid = null
	_body = null

func _growing(seconds: float) -> GrowingSolid:
	_solid = GrowingSolid.new()
	_solid.grow_time = seconds
	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 2.0)
	shape.shape = box
	_body.add_child(shape)
	_solid.add_child(_body)
	_solid.body = _body
	add_child_autofree(_solid)
	await step(1)
	return _solid

func test_it_is_not_solid_before_it_has_finished_growing() -> void:
	# THE WHOLE POINT. A player who arrives early must pass through, not
	# stumble into a half-built wall he cannot see.
	var solid: GrowingSolid = await _growing(1.0)
	solid.begin()
	await step(10)
	assert_gt(solid.progress, 0.0, "test setup: growth did not start")
	assert_lt(solid.progress, 1.0, "test setup: growth finished too fast to observe")
	assert_false(solid.solid, "the obstacle was solid while still growing")

func test_it_becomes_solid_when_growth_completes() -> void:
	var solid: GrowingSolid = await _growing(0.1)
	solid.begin()
	await step(20)
	assert_true(solid.solid, "growth finished without the obstacle becoming solid")

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

func test_collapse_gives_up_solidity_immediately() -> void:
	# Collapsing geometry must stop blocking the moment it starts to go --
	# a player running through the space it used to occupy is the whole
	# reason it is leaving.
	var solid: GrowingSolid = await _growing(0.1)
	solid.begin()
	await step(20)
	assert_true(solid.solid, "test setup: it never became solid")
	solid.collapse()
	await step(1)
	assert_false(solid.solid, "a collapsing obstacle was still blocking")

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
