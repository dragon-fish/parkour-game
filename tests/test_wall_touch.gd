extends ParkourTest

# A hand rests on a wall the body walks past. ✅ THE OWNER: "角色的右手边如果有
# 可以触摸到的墙壁，角色会尝试用手掌碰墙，走胶囊到墙壁的垂线" -- both hands, the
# same rule, whichever side the wall is on.
#
# Built on the real VRM body (untracked), so every test here SKIPS with a note
# when it is absent -- same stance as test_hand_ik.gd.

const TestWorld = preload("res://tests/world_fixture.gd")
const BODY_PATH := "res://assets/models/test.vrm"

var _world: Dictionary = {}
var _extra: Array[Node] = []

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player_with_body() -> Player:
	if not ResourceLoader.exists(BODY_PATH):
		return null
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player._attach_body(load(BODY_PATH))
	await step(3)
	return player

func _skip_note() -> void:
	pending("no humanoid body at %s -- wall touch is unverified in this checkout" % BODY_PATH)

## A wall whose face stands `face_x` from the world origin, tall and long
## enough that the shoulder-height side ray cannot miss it lengthwise.
func _wall_at(face_x: float, height: float = 3.0) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, height, 4.0)
	shape.shape = box
	body.add_child(shape)
	# POSITIONED BEFORE ENTERING THE TREE. Added at the origin and moved after,
	# the wall overlaps the player for the instant it registers with the physics
	# server, and depenetration shoves the capsule 0.61 m sideways -- measured;
	# it cost this suite three "impossible" failures before the fixture was
	# caught doing it.
	body.position = Vector3(face_x + signf(face_x) * 0.3, height * 0.5, 0.0)
	get_tree().root.add_child(body)
	_extra.append(body)

func test_a_wall_on_the_right_gets_the_right_palm() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	# Facing -Z, the body's RIGHT is world -X -- this geometry is what holds
	# the sign in Player._drive_wall_touch().
	_wall_at(-0.7)
	await step(30)
	var state: Dictionary = player.hand_ik.debug()
	assert_gt(float(state["right"]), 0.5, "the right hand never reached for the wall")
	assert_almost_eq(float(state["left"]), 0.0, 0.001, "the far hand reached too")

func test_a_wall_on_the_left_gets_the_left_palm() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	_wall_at(0.7)
	await step(30)
	var state: Dictionary = player.hand_ik.debug()
	assert_gt(float(state["left"]), 0.5, "the left hand never reached for the wall")
	assert_almost_eq(float(state["right"]), 0.0, 0.001, "the far hand reached too")

func test_a_wall_out_of_reach_is_ignored() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	_wall_at(-1.2)
	await step(30)
	var state: Dictionary = player.hand_ik.debug()
	assert_almost_eq(float(state["right"]), 0.0, 0.001,
		"the hand reached for a wall further than the arm")

func test_leaving_the_ground_lets_go() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	# TALL wall, so the shoulder ray still sees it after the lift below --
	# what must end the touch is the MOVE changing, not the wall leaving reach.
	_wall_at(-0.7, 8.0)
	await step(30)
	assert_gt(float(player.hand_ik.debug()["right"]), 0.5, "test setup: never touched")
	# Into the air beside the same wall: standing on the floor, a started
	# Falling lands and is legitimately Walking again within a tick.
	player.global_position.y += 3.0
	player.move_manager.start(Move.FALLING)
	await step(20)
	assert_ne(player.move_manager.current_name, Move.WALKING,
		"test setup: landed already, so nothing here tests the gate")
	var state: Dictionary = player.hand_ik.debug()
	assert_almost_eq(float(state["right"]), 0.0, 0.001,
		"the hand stayed on the wall after the move stopped being Walking")

## A wall square across the path: face toward +z at `face_z`.
func _wall_ahead(face_z: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 0.6)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, 1.5, face_z - 0.3)
	get_tree().root.add_child(body)
	_extra.append(body)

func test_facing_the_wall_puts_both_palms_on_it() -> void:
	# ✅ THE OWNER: "ME里如果几乎面对墙壁时角色会同时将两只手放在墙上."
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	_wall_ahead(-0.7)
	await step(30)
	var state: Dictionary = player.hand_ik.debug()
	assert_gt(float(state["left"]), 0.5, "the left palm never went up")
	assert_gt(float(state["right"]), 0.5, "the right palm never went up")
	var spread: float = absf(player.hand_ik._targets[HandIK.LEFT].global_position.x
		- player.hand_ik._targets[HandIK.RIGHT].global_position.x)
	assert_gt(spread, 0.25, "both palms landed on the same spot (spread %.2f)" % spread)

func test_the_palm_target_stays_off_the_surface() -> void:
	# ✅ THE OWNER: "手掌有可能直接插进墙里面." The target drives the wrist, so it
	# stands off the face along the normal.
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	_wall_at(-0.7)
	await step(30)
	var target: Vector3 = player.hand_ik._targets[HandIK.RIGHT].global_position
	# Face at x = -0.7, normal +x: the target sits clear of the surface.
	assert_gt(target.x, -0.66, "the wrist target is on (or inside) the wall face")

func test_an_idle_arm_is_solved_onto_its_own_animated_pose() -> void:
	# The modifier's ONE influence drives both chains, so the arm nobody asked
	# for must be aimed at wherever the animation already put it -- otherwise a
	# full-strength solve wrenches it toward a stale target (the owner's
	# "右手扭曲到了身体左侧", mirrored).
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	_wall_at(-0.7)
	await step(30)
	var skels: Array[Node] = player.find_children("*", "Skeleton3D", true, false)
	var skeleton := skels[0] as Skeleton3D
	var hand: int = skeleton.find_bone("LeftHand")
	var animated: Vector3 = skeleton.global_transform \
		* skeleton.get_bone_global_pose(hand).origin
	var target: Vector3 = player.hand_ik._targets[HandIK.LEFT].global_position
	assert_lt(target.distance_to(animated), 0.05,
		"the idle left arm is being solved toward a point %.2f m from its own pose"
			% target.distance_to(animated))
