extends ParkourTest

# The first-person eye pivots about the model's head whichever way the view
# turns away from the model. The view is free inside a move's look window
# while the model keeps its own facing (a wall run along its wall, a hang
# square to its ledge, a body standing still), so every offset the eye
# carries has to be expressed in the frame it belongs to: the forward one
# along the VIEW, because the head turns with the view, and the sideways one
# along the MODEL, because it follows where the model's body is. Get either
# frame wrong and turning the view a quarter turn swings the eye off the neck
# -- most of a metre for the wall run's sideways offset.
#
# Structural only: the offsets are whatever the config holds, and the
# assertions are about which frame they move in.

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
	await step(1)

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

func _box(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	get_tree().root.add_child(body)
	_extra.append(body)

## A stand-in head under BodyRoot, so it turns with the MODEL, `offset` from
## the capsule's axis in the model's own frame.
func _attach_head(player: Player, offset: Vector3) -> Node3D:
	var body := Node3D.new()
	body.name = "fake_body"
	var head := Node3D.new()
	head.name = "MHead"
	head.position = offset
	body.add_child(head)
	player.get_node("BodyRoot").add_child(body)
	# As the attach would: the per-tick presentation drivers gate on a body.
	player.body = body
	player.head_node = head
	player.head_rest_local = player.to_local(head.global_position)
	return head

## Turns the view by `radians` (positive left) over `ticks` ticks.
func _turn(player: Player, radians: float, ticks: int) -> void:
	var input: ScriptedInputSource = _world["input"]
	var px: float = -radians / player.config.camera.mouse_sensitivity / float(ticks)
	for i in ticks:
		input.state.look = Vector2(px, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	await step(1)

## Where the eye sits relative to the head, flat, in the MODEL's frame:
## x to the model's right, y along its facing.
func _eye_from_head_in_model_frame(player: Player, head: Node3D) -> Vector2:
	var d: Vector3 = player.camera_rig.global_position - head.global_position
	var yaw: float = player.visual_yaw()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return Vector2(d.dot(right), d.dot(forward))

func test_the_wall_runs_sideways_eye_offset_turns_with_the_model() -> void:
	# The wall run slides the eye away from the wall to follow a model held
	# out from it. That offset is the MODEL's: with the view turned to the
	# edge of the run's window it must still point off the model's side, not
	# off the view's -- along the view it ended up along the wall, behind the
	# shoulders or out past the face.
	var player: Player = await _player()
	# A wall on the left, face at x = -0.6, a platform to jump from beside it.
	_box(Vector3(1.0, 1.0, 2.0), Vector3(-0.05, 2.5, 0.0))
	_box(Vector3(1.0, 8.0, 60.0), Vector3(-1.1, 4.0, -28.0))
	player.global_position = Vector3(0.0, 3.05 + player.collision_half_height(), 0.0)
	player.rotation.y = deg_to_rad(30.0)
	player.pawn_yaw = deg_to_rad(30.0)
	await step(10)
	# The head ON the axis, so the only sideways offset between the two is the
	# rig's own.
	var head: Node3D = _attach_head(player, Vector3(0.0, 0.72, 0.0))
	player.camera_rig.eye_forward = 0.0
	var jump: JumpMove = player.move_manager.move_for(Move.JUMP)
	jump.delay_time_check_auto_moves = 100.0
	var input: ScriptedInputSource = _world["input"]
	player.velocity = player.facing() * 6.0
	input.hold_move(0.0, 1.0)
	input.press_jump()
	await step(20)
	input.release_jump()
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, "test setup: no run")
	# Away from the wall (to the right), up to the window's edge.
	await _turn(player, -deg_to_rad(110.0), 15)
	assert_eq(player.move_manager.current_name, Move.WALL_RUN, "test setup: the run ended")
	var apart: float = absf(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI))
	assert_gt(apart, deg_to_rad(60.0),
		"test setup: the view only turned %.0f degrees off the model" % rad_to_deg(apart))
	var lateral: float = player.camera_rig.extra_eye_lateral
	assert_gt(absf(lateral), 0.1, "test setup: no sideways eye offset on the run")
	var eye: Vector2 = _eye_from_head_in_model_frame(player, head)
	assert_almost_eq(eye.x, lateral, 0.03,
		"the eye is %.2f m off the model's side instead of %.2f" % [eye.x, lateral])
	assert_almost_eq(eye.y, 0.0, 0.03,
		"the eye is %.2f m along the model's facing from its head, %.0f degrees into the turn"
			% [eye.y, rad_to_deg(apart)])

func test_the_eye_keeps_its_place_ahead_of_the_head_as_the_view_turns() -> void:
	# The other half of the pivot: with no sideways offset the eye's relation to
	# the head is fixed in the VIEW's frame, so a model holding its facing
	# while the view turns carries its head round under the eye rather than
	# leaving it behind. A head off the axis is what tells the two apart.
	var player: Player = await _player()
	var head: Node3D = _attach_head(player, Vector3(0.0, 0.72, 0.1))
	player.camera_rig.eye_forward = 0.13
	await step(10)
	var view := func() -> Vector3:
		return player.global_basis.inverse() \
			* (player.camera_rig.global_position - head.global_position)
	var before: Vector3 = view.call()
	# Standing still, the model holds while the view turns -- short of the
	# angle at which it steps round.
	var hold: float = deg_to_rad(player.config.pawn.turn_in_place_angle_deg) * 0.8
	await _turn(player, hold, 10)
	var apart: float = absf(wrapf(player.rotation.y - player.visual_yaw(), -PI, PI))
	assert_gt(apart, deg_to_rad(30.0), "test setup: the model turned with the view")
	var after: Vector3 = view.call()
	var flat := Vector2(after.x - before.x, after.z - before.z)
	assert_lt(flat.length(), 0.02,
		"the eye moved %.3f m relative to the head in the view's frame at %.0f degrees"
			% [flat.length(), rad_to_deg(apart)])
