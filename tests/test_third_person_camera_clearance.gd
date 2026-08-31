extends ParkourTest

# The third-person camera is a SPHERE to the world, not a point.
#
# A camera resting exactly on a surface has that surface cutting through its
# near plane, which is what "half the shot is inside the wall" is. The near
# plane has width and a ray probe cannot know that, so what is pinned here is
# the clearance itself: whatever the probe backed away from, the camera ends up
# at least CameraConfig.third_person_probe_radius clear of it.
#
# The radius is a dial and is deliberately not asserted at any value. These
# cases read it out of the config, so retuning it retunes them.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _walls: Array[StaticBody3D] = []

func after_each() -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _rig() -> CameraRig:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var rig: CameraRig = _world["player"].camera_rig
	rig.third_person = true
	return rig

## A wall whose near FACE is the plane z = `face_z`, wide and tall enough that
## nothing gets past it around the edges. `gap` leaves a slit that wide centred
## on x = 0, built as two slabs, for the case a ray threads and a sphere cannot.
func _wall(rig: CameraRig, face_z: float, gap: float = 0.0) -> void:
	var half: float = 10.0
	var spans: Array = [[-half, half]] if gap <= 0.0 \
		else [[-half, -gap * 0.5], [gap * 0.5, half]]
	for span in spans:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var width: float = span[1] - span[0]
		box.size = Vector3(width, 20.0, 0.4)
		shape.shape = box
		wall.add_child(shape)
		# tree.root, the way world_fixture.build() parents its own floor.
		rig.get_tree().root.add_child(wall)
		wall.global_position = Vector3((span[0] + span[1]) * 0.5, 0.0, face_z + 0.2)
		_walls.append(wall)

## Where the camera actually ends up, in world space.
func _camera_world(rig: CameraRig) -> Vector3:
	return rig.to_global(rig._third_person_position())

func test_the_camera_keeps_its_radius_clear_of_a_wall_behind_it() -> void:
	# The camera sits at +Z of an unrotated body (third_person_back is a
	# positive local z), so the wall it backs into goes there.
	var rig: CameraRig = await _rig()
	var radius: float = rig._config.camera.third_person_probe_radius
	var face_z: float = rig.global_position.z + 1.5
	_wall(rig, face_z)
	await step(5)

	var camera := _camera_world(rig)
	assert_lt(camera.z, face_z,
		"the camera ended up on the far side of the wall")
	assert_gte(face_z - camera.z, radius,
		"the camera rested %.3f m off the wall, inside its own probe radius %.3f"
			% [face_z - camera.z, radius])

func test_the_camera_does_not_thread_a_gap_narrower_than_itself() -> void:
	# What a ray probe gets wrong even when nothing is "flush": a centre line
	# slips through a corner seam or between two slabs and reports the far side
	# clear, so the camera lands wholly inside geometry it never touched.
	var rig: CameraRig = await _rig()
	rig._shoulder = CameraRig.Shoulder.CENTRED
	var radius: float = rig._config.camera.third_person_probe_radius
	var face_z: float = rig.global_position.z + 1.5
	# Narrower than the sphere is wide, so it cannot pass however it is aimed.
	_wall(rig, face_z, radius)
	await step(5)

	assert_lt(_camera_world(rig).z, face_z,
		"the camera went through a gap narrower than its own diameter")
