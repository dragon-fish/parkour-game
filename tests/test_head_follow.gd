extends ParkourTest

# The eye rides the attached body's head, and keeps its own resting place while
# doing it.
#
# Those are two requirements, and the first implementation could only ever
# satisfy one at a time: it lerped the eye's POSITION toward the head node's
# position, so a strength below 1 left the head sliding through the view and a
# strength of 1 parked the camera on the head node's own origin -- throwing away
# eye_height and the small forward placement a first-person camera wants.
#
# The owner found it from the symptom: a body's neck kept passing through the
# view during a run, while standing still looked fine. If the eye rode the head,
# the head could never reach it.
#
# Following the head's DISPLACEMENT FROM REST satisfies both at once, which is
# what these pin.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## A head node parked well AWAY from where the eye belongs, deliberately: a real
## model's head node sits wherever its author put it, which is what the old
## implementation dragged the camera toward.
func _attach_head(player: Player, at: Vector3) -> Node3D:
	var body := Node3D.new()
	body.name = "fake_body"
	var head := Node3D.new()
	head.name = "MHead"
	body.add_child(head)
	player.get_node("BodyRoot").add_child(body)
	head.global_position = player.global_position + at
	player.head_node = head
	player.head_rest_local = player.to_local(head.global_position)
	return head

func test_a_head_at_rest_leaves_the_eye_exactly_where_it_was() -> void:
	# THE PLACEMENT REQUIREMENT. The eye is put where a first-person camera
	# belongs -- eye_height, a little ahead of the neck -- and attaching a body
	# must not move it. The old blend did, by a quarter of a metre at the
	# default strength, because the head node was nowhere near the eye.
	var player: Player = await _player()
	var rig: CameraRig = player.camera_rig
	await step(5)
	var before: Vector3 = rig.position

	_attach_head(player, Vector3(0.0, -0.16, 0.05))
	await step(5)
	assert_almost_eq(rig.position.distance_to(before), 0.0, 0.002, \
		"attaching a body moved the eye %.3f m from where it was placed" \
		% rig.position.distance_to(before))

func test_the_eye_rides_the_head_one_for_one() -> void:
	# THE RIDING REQUIREMENT, and the one the neck clipping was really about:
	# at full strength there is NO relative motion left between the eye and the
	# head, so body geometry can never reach the camera.
	var player: Player = await _player()
	var rig: CameraRig = player.camera_rig
	var head: Node3D = _attach_head(player, Vector3(0.0, -0.16, 0.05))
	await step(5)
	var before: Vector3 = rig.position

	const BOB := 0.09  # the measured stride bob of the owner's own body
	head.global_position += Vector3(0.0, BOB, 0.0)
	await step(1)
	assert_almost_eq(rig.position.y - before.y, BOB, 0.002, \
		"the head moved %.3f m and the eye followed %.3f m -- the difference is \
what slides through the view" % [BOB, rig.position.y - before.y])

func test_half_strength_follows_half_of_it() -> void:
	var player: Player = await _player()
	var rig: CameraRig = player.camera_rig
	player.config.camera.camera_head_follow_strength = 0.5
	var head: Node3D = _attach_head(player, Vector3(0.0, -0.16, 0.05))
	await step(5)
	var before: Vector3 = rig.position

	head.global_position += Vector3(0.0, 0.09, 0.0)
	await step(1)
	assert_almost_eq(rig.position.y - before.y, 0.045, 0.002, \
		"half strength did not follow half the motion")

func test_zero_strength_lets_no_head_motion_through_at_all() -> void:
	# The opt-out: this is the camera every setup without a body already has,
	# and a body must not perturb it.
	#
	# Tolerance rather than exact equality, and the reason is worth keeping: the
	# eye's own bob/dip drifts about 0.08 mm between ticks all by itself, so
	# equality would be asserting that base_position is static, which is not the
	# claim. The head below moves HALF A METRE -- anything leaking through would
	# be centimetres, three orders of magnitude above this bound.
	var player: Player = await _player()
	var rig: CameraRig = player.camera_rig
	player.config.camera.camera_head_follow_strength = 0.0
	var head: Node3D = _attach_head(player, Vector3(0.0, -0.16, 0.05))
	await step(5)
	var before: Vector3 = rig.position

	head.global_position += Vector3(0.3, 0.4, 0.5)
	await step(1)
	assert_almost_eq(rig.position.distance_to(before), 0.0, 0.001, 		"a disabled follow moved the eye %.4f m" % rig.position.distance_to(before))
