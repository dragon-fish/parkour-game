extends ParkourTest

# Inside the forward arc the run band plays ONE forward clip for every
# direction in it, so nothing on screen says the body is travelling 45 degrees
# off its facing. The hips carry that angle instead, and the spine takes it
# back off the upper body.
#
# STRUCTURE, NOT FEEL. What is pinned here is that the legs turn, that the
# shoulders do not go with them, and that the turn is refused wherever an
# authored octant clip is already turned -- never how far it goes, which is a
# number to be looked at rather than asserted (see the tuning-dials-not-rules
# note).

const TestWorld = preload("res://tests/world_fixture.gd")

const FULL_CLIPS: PackedStringArray = [
	"idle", "Sprint",
	"Walk", "Walk_Fwd", "Walk_Fwd_L", "Walk_Fwd_R", "Walk_L", "Walk_R",
	"Walk_Bwd", "Walk_Bwd_L", "Walk_Bwd_R",
	"Jog_Fwd", "Jog_Fwd_L", "Jog_Fwd_R", "Jog_Left", "Jog_Right",
	"Jog_Bwd", "Jog_Bwd_L", "Jog_Bwd_R",
]

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _animator() -> CharacterAnimator:
	var body := TestWorld.build_stub_body("", Vector3.ZERO, true, FULL_CLIPS)
	_world = TestWorld.build(get_tree(), MovementConfig.new(), body)
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"].get_node("BodyRoot").get_node("CharacterAnimator")

## Sets the body travelling at `velocity` from an unrotated facing, the way
## tests/test_animation_direction.gd does -- the routing reads velocity, so it
## does not have to be accelerated into.
func _travel(velocity: Vector3) -> void:
	var player: Player = _world["player"]
	player.rotation.y = 0.0
	player.velocity = velocity
	player.move_manager.start(Move.WALKING)

## Where a body facing -Z ends up pointing once `twist` is applied the way the
## modifier applies it. Asserting against THIS rather than against the angle's
## sign is the whole point of these two tests: an implementation and a test
## that both name the sign can agree with each other and both face backwards,
## which is exactly what happened -- the legs turned away from the direction of
## travel while the shoulders swung into it.
func _aimed_by(twist: float) -> Vector3:
	return Basis(Vector3.UP, twist) * Vector3(0.0, 0.0, -1.0)

func test_the_hips_carry_a_diagonal_the_clip_does_not() -> void:
	var animator: CharacterAnimator = await _animator()
	var travel := Vector3(-5.0, 0.0, -5.0)
	_travel(travel)
	var twist: float = animator.lower_body_twist()
	assert_almost_eq(absf(twist), PI / 4.0, 0.02, "a 45-degree diagonal is the angle owed")
	assert_almost_eq(_aimed_by(twist).dot(travel.normalized()), 1.0, 0.01,
		"ahead-and-left must aim the legs ahead and left")

func test_the_sign_is_not_flipped() -> void:
	# The mirror of the case above, because a sign error that happens to be
	# symmetric passes either one on its own.
	var animator: CharacterAnimator = await _animator()
	var travel := Vector3(5.0, 0.0, -5.0)
	_travel(travel)
	assert_almost_eq(_aimed_by(animator.lower_body_twist()).dot(travel.normalized()), \
		1.0, 0.01, "ahead-and-right must aim the legs ahead and right")

func test_a_straight_run_owes_nothing() -> void:
	var animator: CharacterAnimator = await _animator()
	_travel(Vector3(0.0, 0.0, -6.0))
	assert_almost_eq(animator.lower_body_twist(), 0.0, 0.001, "straight ahead")

func test_an_authored_octant_is_not_turned_again() -> void:
	# Outside the arc the eight-way set is playing and already carries the
	# direction in the clip. Turning the hips on top of it is the double-count
	# that made the model judder and the first-person camera shake.
	var animator: CharacterAnimator = await _animator()
	_travel(Vector3(-6.0, 0.0, 0.0))
	assert_eq(animator.lower_body_twist(), 0.0, "strafing left is authored")
	after_each()
	animator = await _animator()
	_travel(Vector3(-4.0, 0.0, 4.0))
	assert_eq(animator.lower_body_twist(), 0.0, "backpedalling left is authored")

func test_the_walk_band_is_authored_too() -> void:
	# Below the run band every direction has its own Walk clip, arc or no arc.
	var animator: CharacterAnimator = await _animator()
	_travel(Vector3(-1.4, 0.0, -1.4))
	assert_eq(animator.lower_body_twist(), 0.0, "the walk band strafes on its own set")

func test_the_shoulders_do_not_go_with_the_legs() -> void:
	# The hips turn and the spine subtracts the same angle, so what is left is
	# a twist at the waist rather than the whole body turned. Asked of the
	# modifier's own bookkeeping: a body with no humanoid skeleton has no bones
	# to measure, and the stub is deliberately one of those.
	var look := HeadLook.new()
	look.request_lower_twist(deg_to_rad(45.0))
	assert_almost_eq(look._wanted_twist, deg_to_rad(45.0), 0.001, "the request lands")
	look.request_lower_twist(deg_to_rad(400.0))
	assert_almost_eq(look._wanted_twist, deg_to_rad(HeadLook.LOWER_TWIST_LIMIT_DEG), \
		0.001, "and is clamped to the limit")
	look.free()

func test_the_limit_clears_the_arc() -> void:
	# in_forward_arc()'s tolerance lets a 45-degree diagonal read a shade over
	# 45, so a limit sitting exactly on forward_arc_deg would clip the one
	# direction this exists to serve.
	var pawn := PawnConfig.new()
	assert_gt(HeadLook.LOWER_TWIST_LIMIT_DEG, pawn.forward_arc_deg, \
		"the twist limit must clear the arc it serves")
