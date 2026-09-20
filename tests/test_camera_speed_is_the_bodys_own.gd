extends ParkourTest

# What the camera is told about speed is the BODY'S OWN, and the bob is told
# about footfalls only.
#
# Reported on the subway's train roof: standing still on sixty metres a second
# of train maxed the FOV and ran the bob at a sprint nobody was making, because
# the speed fed to the camera is measured from world displacement. And down a
# chute (RampSlide) the camera bobbed at a sprinter's cadence to a body that
# takes no steps at all. Structural: no amounts of shake are asserted here.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _extra: Array[Node] = []


func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}


func test_what_carries_the_body_is_not_the_bodys_speed() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	# The fixture's floor is out of the way: the body stands on a platform.
	_world["floor"].global_position = Vector3(0.0, -50.0, 0.0)
	var platform := AnimatableBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 1.0, 400.0)
	shape.shape = box
	platform.add_child(shape)
	get_tree().root.add_child(platform)
	_extra.append(platform)
	platform.global_position = Vector3(0.0, -0.5, 0.0)
	var player: Player = _world["player"]
	player.global_position = Vector3(0.0, 0.95, 0.0)
	await step(30)
	assert_true(player.grounded, "the body has settled on the platform")
	var started_at := player.global_position.z
	for i in 60:
		platform.global_position.z -= 30.0 / 60.0
		await step(1)
	assert_lt(player.global_position.z, started_at - 15.0, "the platform carried the body along")
	assert_lt(player.travel_speed(), 3.0, "and none of that is the body's own speed: the camera must not hear 30 m/s")


func test_a_move_with_no_footfalls_feeds_the_bob_no_stride() -> void:
	assert_true(MoveConfig.new().footfall_bob, "on its feet unless a move says otherwise")
	assert_false(SlideConfig.new().footfall_bob, "a slide takes no steps")
	assert_false(RampSlideConfig.new().footfall_bob, "nor does a body carried down a chute on its seat")

	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	var rig: CameraRig = (_world["player"] as Player).camera_rig
	var before: float = rig._bob_phase
	rig.update_effects(0.1, 12.0, true, 0.0)
	assert_eq(rig._bob_phase, before, "12 m/s of sliding turns the bob's phase not at all")
	rig.update_effects(0.1, 12.0, true)
	assert_gt(rig._bob_phase, before, "and 12 m/s on foot does")
