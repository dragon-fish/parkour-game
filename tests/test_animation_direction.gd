extends ParkourTest

# Which way the body is TRAVELLING picks the clip, not which way it is facing.
#
# The packs ship eight-way sets for the walk, the jog and the crouch, and this
# is the arithmetic that reaches into them. Tested because a sign error here is
# invisible in the code and unmistakable on screen -- the body strafes left
# while sliding right -- and because this project has already had one: an
# earlier torso twist used signed_angle_to() and clamped backward diagonals to
# the same side as forward ones.
#
# The velocities below are read as-is, without stepping: a tick of WalkingMove
# would rewrite them from the input, and what is under test is the mapping from
# a velocity to a clip name.

const TestWorld = preload("res://tests/world_fixture.gd")

## Both packs' full eight-way sets, plus the forward clips the bands reach for.
const FULL_CLIPS: Array = [
	&"Idle", &"Sprint", &"Walk", &"Crouch_Idle",
	&"Jog_Fwd", &"Jog_Fwd_L", &"Jog_Fwd_R", &"Jog_Left", &"Jog_Right",
	&"Jog_Bwd", &"Jog_Bwd_L", &"Jog_Bwd_R",
	&"Walk_Fwd", &"Walk_Fwd_L", &"Walk_Fwd_R", &"Walk_L", &"Walk_R",
	&"Walk_Bwd", &"Walk_Bwd_L", &"Walk_Bwd_R",
	&"Crouch_Fwd", &"Crouch_Fwd_L", &"Crouch_Fwd_R", &"Crouch_Left",
	&"Crouch_Right", &"Crouch_Bwd", &"Crouch_Bwd_L", &"Crouch_Bwd_R",
]

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _animator_with(clips: Array) -> CharacterAnimator:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var body := Node3D.new()
	body.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in clips:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player._wire_body_animation(body)
	return player.get_node("BodyRoot").get_node("CharacterAnimator")

## Faces down -Z (Godot's forward, and the player's rest facing) and travels at
## `velocity`, so a -Z velocity is straight ahead and +X is to the right.
func _travel(player: Player, velocity: Vector3) -> void:
	player.rotation.y = 0.0
	player.velocity = velocity

func _asked_for(clips: Array, move: StringName, velocity: Vector3) -> String:
	var animator: CharacterAnimator = await _animator_with(clips)
	var player: Player = _world["player"]
	player.move_manager.start(move)
	_travel(player, velocity)
	return String(animator._target_animation())

# --- the run band splits by direction -----------------------------------------

func test_running_straight_ahead_takes_the_jog() -> void:
	# The sprint was here, as the forward octant's exception to the jog's
	# eight-way set. Its stride is far larger than this project wants, so the
	# exception is gone and every direction is the jog's -- which is also the
	# only set that reaches running pace in all eight.
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(0.0, 0.0, -6.0)),
		"Jog_Fwd", "a straight run did not take the jog")

func test_strafing_at_speed_takes_the_jog() -> void:
	# The jog is the only eight-way set that reaches running pace. Sideways
	# there is no alternative that is not a rotated or reversed sprint.
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(6.0, 0.0, 0.0)),
		"Jog_Right", "strafing right at speed")
	after_each()
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(-6.0, 0.0, 0.0)),
		"Jog_Left", "strafing left at speed")

func test_running_backwards_takes_the_backward_jog() -> void:
	# THE HACK THIS REPLACES: with no backward clip at all, the old answer was
	# the forward run played in reverse, whose own comment admitted the foot
	# contacts and the arm swing were both wrong.
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(0.0, 0.0, 6.0)),
		"Jog_Bwd", "running backwards")

func test_the_diagonals_do_not_cross_over() -> void:
	# ⚠️ THE SIGN. Forward-and-right must not resolve to the forward-LEFT clip,
	# and the backward diagonals must not fold onto the forward ones -- which is
	# exactly the mistake an earlier signed_angle_to() made in the torso twist.
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(5.0, 0.0, -5.0)),
		"Jog_Fwd_R", "ahead and to the right")
	after_each()
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(-5.0, 0.0, -5.0)),
		"Jog_Fwd_L", "ahead and to the left")
	after_each()
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(5.0, 0.0, 5.0)),
		"Jog_Bwd_R", "behind and to the right")
	after_each()
	assert_eq(await _asked_for(FULL_CLIPS, Move.WALKING, Vector3(-5.0, 0.0, 5.0)),
		"Jog_Bwd_L", "behind and to the left")

# --- the slower bands use their own sets ---------------------------------------

func test_ctrl_is_what_reaches_the_walk_set() -> void:
	# There is no walk BAND any more: without Ctrl a body crosses everything
	# below a run in a handful of frames, and threading a walk loop through them
	# buys a cadence nobody can see. Ctrl is the walk, and it is the only way to
	# the walk's own eight-way set.
	var animator: CharacterAnimator = await _animator_with(FULL_CLIPS)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	_travel(player, Vector3(2.0, 0.0, 0.0))

	assert_eq(String(animator._target_animation()), "Jog_Right",
		"strafing at two metres a second without Ctrl went looking for a walk band")

	var creep := MoveInput.new()
	creep.move = Vector2(1.0, 0.0)
	creep.walk_held = true
	player.last_input = creep
	assert_eq(String(animator._target_animation()), "Walk_R",
		"Ctrl did not reach the walk's own set")

func test_a_crouched_strafe_stays_crouched() -> void:
	assert_eq(await _asked_for(FULL_CLIPS, Move.CROUCH, Vector3(2.0, 0.0, 0.0)),
		"Crouch_Right", "strafing while crouched")

# --- bodies without the full set ------------------------------------------------

func test_a_partial_set_falls_back_within_its_own_family() -> void:
	# The FREE tier ships Crouch_Fwd and none of its seven neighbours. Running
	# the forward clip during a strafe is wrong, but it is the same body at the
	# same cadence -- which the next candidate down the list would not be.
	var partial: Array = [&"Idle", &"Sprint", &"Crouch_Idle", &"Crouch_Fwd", &"Walk"]
	assert_eq(await _asked_for(partial, Move.CROUCH, Vector3(2.0, 0.0, 0.0)),
		"Crouch_Fwd", "a crouch with no strafe clip")

func test_a_body_with_no_set_at_all_still_gets_the_reversed_twin() -> void:
	# The fox, and every body before the packs were bought. The reversed twin is
	# built by Player._wire_body_animation() for the clips in _REVERSIBLE_CLIPS,
	# and it stays the answer for a body that has nothing better.
	var fox: Array = [&"idle", &"run"]
	assert_eq(await _asked_for(fox, Move.WALKING, Vector3(0.0, 0.0, 6.0)),
		"run" + Player.BACKWARD_SUFFIX, "a body with no eight-way set, backwards")
