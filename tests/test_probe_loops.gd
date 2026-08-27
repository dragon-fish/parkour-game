extends ParkourTest

# A probe that fires must be able to make progress, or it fires again next tick
# from the same spot, forever.
#
# TWO WAYS THIS HAPPENS, both at full tick rate (dozens of transitions a
# second) with a body reading h 0.00 v 0.00:
#
#   Walking -> Falling -> SpeedVault -> Walking -> Falling -> SpeedVault ...
#
# once beside a block after a grab, and once backing slowly off a roof edge
# until it drops.
#
# NEITHER LOOP IS A BUG IN THE MOVE IT LOOPS THROUGH. SpeedVault behaves
# correctly: fired from a standstill it has no speed to carry the body anywhere,
# so it ends where it began. IntoGrab behaves correctly too: it reaches, fails,
# and gives up honestly. What is wrong in both cases is that the ENTRY
# CONDITION can be satisfied twice from the same place -- so the state machine
# does exactly what it was told, as fast as the frame loop lets it.

const TestWorld = preload("res://tests/world_fixture.gd")

## Freed by after_each(); TestWorld.teardown() frees only the player and floor.
var _extra: Array[Node] = []
var _world: Dictionary = {}

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
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

## A block the player is standing right up against, its top `height` above their
## feet -- the shape both of the owner's screenshots had in front of them.
func _face_at(player: Player, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, height, 2.0)
	shape.shape = box
	body.add_child(shape)
	player.get_parent().add_child(body)
	var feet: float = player.global_position.y - player.current_capsule_height() * 0.5
	# Face just in front of the body, which is what touching() answers about.
	body.global_position = Vector3(player.global_position.x, feet + height * 0.5,
			player.global_position.z - 1.2)
	_extra.append(body)
	return body

# --- the vault ----------------------------------------------------------------

func test_a_body_at_a_standstill_against_a_face_does_not_vault() -> void:
	# THE REGRESSION, and the escape hatch it came through was written for
	# something else entirely. AirborneMove's vault gate is
	#
	#     closing or touching(face_point)
	#
	# where `closing` divides by horizontal speed and is therefore false at a
	# standstill. The touching() half exists for a WALL CLIMB topping out --
	# its own comment says so, "the body is going straight up against a surface
	# it is already in contact with" -- but a body merely RESTING against a face
	# satisfies touching() just as completely while going nowhere.
	var player: Player = await _player()
	_face_at(player, 0.9)
	await step(2)
	player.velocity = Vector3.ZERO
	player.move_manager.start(Move.FALLING)
	var falling := player.move_manager.move_for(Move.FALLING)
	var probed: StringName = falling.probe_transition()
	assert_ne(probed, Move.SPEED_VAULT,
		"a motionless body vaulted, which is the loop the owner filmed")

func test_a_rising_body_against_a_face_still_vaults() -> void:
	# The pair, and the case the bypass was actually written for: a 3.5 m wall
	# where the climb tops out with the edge too LOW to grab and a vault that
	# will not commit leaves the player sliding back down. Losing this would
	# trade one reported bug for another.
	var player: Player = await _player()
	_face_at(player, 0.9)
	await step(2)
	player.velocity = Vector3(0.0, 2.0, 0.0)
	player.move_manager.start(Move.FALLING)
	var falling := player.move_manager.move_for(Move.FALLING)
	var probed: StringName = falling.probe_transition()
	assert_eq(probed, Move.SPEED_VAULT,
		"a body climbing a face was refused the vault at the top")

# --- the reach ------------------------------------------------------------------

func test_a_reach_gives_up_once_the_body_is_back_on_the_floor() -> void:
	# A jump too weak to reach a ledge triggers an infinite IntoGrab<->Falling
	# loop if landing back on the floor is not read as a reason to give up.
	#
	# carry_ballistically() runs move_and_slide() and sets grounded, so the
	# answer was available the whole time and simply went unread: a jump too
	# weak to get the hands to the lip drops the body back onto the floor, where
	# it then spent the rest of max_duration (1.5 s) with its input frozen,
	# reaching for something above it.
	var player: Player = await _player()
	var reach := player.move_manager.move_for(Move.INTO_GRAB)
	assert_not_null(reach, "there is no IntoGrabMove to ask")
	# A ledge it will never touch, far enough ahead that touching() cannot fire.
	player.pending_ledge = {"valid": true,
		"edge": player.global_position + Vector3(0.0, 2.4, -4.0),
		"face_normal": Vector3(0.0, 0.0, 1.0), "face_point":
		player.global_position + Vector3(0.0, 2.0, -4.0), "face_distance": 0.5}
	player.move_manager.start(Move.INTO_GRAB)
	player.velocity = Vector3.ZERO
	# Resting on the fixture floor, which is where a jump that fell short ends.
	player.set_grounded(true)
	var result: StringName = reach.physics_update(1.0 / 60.0, MoveInput.new())
	assert_eq(result, Move.FALLING,
		"a reach from a body standing on the floor returned %s" % result)

func test_a_reach_has_a_cooldown_at_all() -> void:
	# THE HALF THAT ACTUALLY BREAKS THE LOOP, and it is a number rather than
	# a mechanism. Handing back to Falling is not enough on its own:
	# AirborneMove asks its grab question BEFORE its landing question, and
	# ledge_query()'s height gate is measured from the FEET -- so a ledge inside
	# [min_wall_height, ledge_max_height] of the floor stays "valid and within
	# reach" from a standing start indefinitely, and Falling sends the body
	# straight back into the reach it just abandoned.
	#
	# IntoGrabConfig.redo_move_time must stay above zero: it is the one move
	# that can be re-entered from the very state it hands back to, so a zero
	# cooldown here reopens exactly the loop this file is about.
	#
	# THE MECHANISM IS NOT RE-TESTED HERE. MoveManager arms redo_move_time on
	# every real transition out and can_enter() checks it before every
	# transition back in; test_move_manager.gd owns both, including the fact
	# that start() deliberately CLEARS a live cooldown -- which is what makes
	# driving this by hand from start() prove nothing at all.
	var player: Player = await _player()
	assert_gt(player.config.into_grab.redo_move_time, 0.0,
		"IntoGrab has no cooldown, so Falling can re-enter it on the next tick")
