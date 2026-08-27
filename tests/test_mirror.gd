extends ParkourTest

# The mirror's invariants -- not its look.
#
# Nothing here pins how dirty a mirror is, how big the glass is, or what
# fraction of the viewport the reflection renders at. Those are judged by
# standing in front of one, and a test that pins them fails on every retune and
# never once on a bug (see docs/feel-backlog.md 57).
#
# What IS pinned is the handful of things that break with no visible error, or
# with a symptom nobody would trace back here:
#
#   * a LEFT-handed reflection basis -- every surface in the mirror renders
#     inside-out, and the reflection maths still "looks reasonable" in a debug
#     print
#   * the glass reaching its own reflection camera -- a mirror inside a mirror
#     inside a mirror, at whatever framerate survives it
#   * the first-person body variant reaching the reflection -- you walk up to a
#     mirror and your reflection has no head

const LAB := "res://scenes/debug_levels/mirror_lab.tscn"

## A mirror at the origin facing -Z, which is the convention Mirror.plane()
## builds from an identity transform.
func _plane() -> Plane:
	return Plane(Vector3(0.0, 0.0, -1.0), Vector3.ZERO)

func _eye_at(from: Vector3, looking_at: Vector3) -> Transform3D:
	return Transform3D(Basis(), from).looking_at(looking_at, Vector3.UP)

func test_the_reflected_eye_is_the_same_distance_on_the_other_side() -> void:
	var plane := _plane()
	var eye := _eye_at(Vector3(3.0, 2.0, -4.0), Vector3(0.0, 1.5, 0.0))
	var reflected := Mirror.reflect_across(eye, plane)
	assert_almost_eq(absf(plane.distance_to(reflected.origin)),
		absf(plane.distance_to(eye.origin)), 0.0001,
		"the reflected eye is not the same distance from the glass")
	assert_lt(plane.distance_to(eye.origin) * plane.distance_to(reflected.origin), 0.0,
		"the reflected eye landed on the same side of the glass as the real one")

func test_reflecting_twice_returns_the_original_eye() -> void:
	# A reflection is its own inverse. This catches a normal used with the wrong
	# sign somewhere in the chain, which otherwise shows up only as a reflection
	# that drifts the wrong way when you walk.
	var plane := _plane()
	var eye := _eye_at(Vector3(-2.5, 1.7, -6.0), Vector3(0.4, 1.2, 0.0))
	var back := Mirror.reflect_across(Mirror.reflect_across(eye, plane), plane)
	assert_true(back.origin.is_equal_approx(eye.origin), "the position did not come back")
	assert_true((-back.basis.z).is_equal_approx(-eye.basis.z), "the facing did not come back")

func test_the_reflected_basis_stays_right_handed() -> void:
	# THE ONE THAT IS INVISIBLE IN A DEBUG PRINT. Reflecting all three axes of a
	# basis gives determinant -1, which flips triangle winding: every surface in
	# the mirror renders inside-out, and the numbers still look plausible.
	# Mirror.reflect_across rebuilds through looking_at specifically to avoid it.
	var plane := _plane()
	for target in [Vector3(0.0, 1.5, 0.0), Vector3(2.0, 0.5, 0.0), Vector3(-1.0, 3.0, 0.0)]:
		var eye := _eye_at(Vector3(1.0, 1.8, -5.0), target)
		var reflected := Mirror.reflect_across(eye, plane)
		assert_gt(reflected.basis.determinant(), 0.0,
			"reflection toward %s produced a left-handed basis" % target)

func test_a_straight_on_eye_reflects_straight_back() -> void:
	# The degenerate case the looking_at rebuild could have failed on: forward
	# exactly along the plane normal, where a naive up vector is parallel to it.
	var plane := _plane()
	var eye := _eye_at(Vector3(0.0, 1.6, -5.0), Vector3(0.0, 1.6, 0.0))
	var reflected := Mirror.reflect_across(eye, plane)
	assert_true(reflected.origin.is_equal_approx(Vector3(0.0, 1.6, 5.0)),
		"straight-on reflection landed at %v" % reflected.origin)
	assert_true((-reflected.basis.z).is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"the straight-on reflection is not looking back at the glass")

func _lab_mirror() -> Mirror:
	var lab := (load(LAB) as PackedScene).instantiate()
	add_child_autofree(lab)
	await step(10)
	return lab.get_node("Mirror") as Mirror

func test_the_glass_cannot_appear_in_its_own_reflection() -> void:
	var mirror: Mirror = await _lab_mirror()
	var camera := mirror.get_node("Reflection/ReflectionCamera") as Camera3D
	var glass := mirror.get_node("Glass") as MeshInstance3D
	assert_eq(camera.cull_mask & glass.layers, 0,
		"the reflection camera can see the glass -- a mirror inside a mirror, forever")

func test_the_reflection_shows_the_body_variant_that_has_a_head() -> void:
	# Arena readies AFTER its children, so a Mirror asking its parent for a
	# MovementConfig during _ready() gets null and quietly builds a mask with no
	# body handling at all. The symptom is a headless reflection and no error.
	var mirror: Mirror = await _lab_mirror()
	var camera := mirror.get_node("Reflection/ReflectionCamera") as Camera3D
	var config := MovementConfig.new().camera
	assert_eq(camera.cull_mask & config.first_person_body_layers, 0,
		"the reflection draws the headless first-person body")
	assert_ne(camera.cull_mask & config.third_person_body_layers, 0,
		"the reflection cannot see the full-head body at all")

func test_the_world_still_reaches_the_reflection() -> void:
	# Every ordinary mesh in this project is on layer 1. A mask built by
	# assignment rather than by clearing bits would drop the entire level and
	# leave a mirror showing nothing but sky -- the same failure
	# test_first_person_body.gd guards for the main camera.
	var mirror: Mirror = await _lab_mirror()
	var camera := mirror.get_node("Reflection/ReflectionCamera") as Camera3D
	assert_ne(camera.cull_mask & 1, 0, "the reflection camera cannot see layer 1")


## THE PAIRING. Mirror.reflect_across rebuilds a right-handed basis through
## Basis.looking_at, and looking_at gets there by negating the camera's X --
## so what the reflection viewport holds is the true mirror image flipped about
## its vertical centre line. shaders/mirror.gdshader undoes that with
## `1.0 - SCREEN_UV.x`. Neither half is correct alone.
##
## A MIRROR THAT DOES NOT INVERT LEFT AND RIGHT IS WRONG, confirmed by two
## independent symptoms: a first-person reflection that turns its head the
## same way you turn yours, and a third-person view where the body and its
## reflection visibly do not mirror each other at all. This test pins the
## inversion so the camera-side flip and the shader-side flip cannot drift
## apart again.
##
## COMPARE NORMALISED UV, NOT PIXELS. The reflection renders at
## resolution_scale, so the two viewports have different pixel sizes;
## comparing raw unproject_position() output across them produces a false
## mismatch that is only a unit difference, not a flip.
##
## If anyone ever makes the node produce a true reflection, the shader's flip
## has to go in the same commit and this test with it.

const FLIP_TOLERANCE := 0.005

func _reflection_uv_pair(mirror: Mirror, point: Vector3) -> Array:
	var viewport := mirror.get_node("Reflection") as SubViewport
	var reflection_camera := viewport.get_node("ReflectionCamera") as Camera3D
	var main := get_tree().root.get_camera_3d()
	var plane := mirror.plane()
	var mirrored := point - 2.0 * plane.distance_to(point) * plane.normal
	var expected: Vector2 = main.unproject_position(mirrored) 		/ Vector2(get_tree().root.get_visible_rect().size)
	var actual: Vector2 = reflection_camera.unproject_position(point) / Vector2(viewport.size)
	return [expected, actual]

func test_the_reflection_lines_up_vertically_with_a_real_mirror() -> void:
	# True in ANY correct implementation, flip or no flip -- so this is the half
	# of the contract that survives a refactor. A mismatch here means the
	# reflected camera's pitch, height or projection is wrong, which no amount
	# of shader UV work can rescue.
	var mirror: Mirror = await _lab_mirror()
	for point in [Vector3(-4.6, 1.1, -1.4), Vector3(4.2, 1.6, -2.0), Vector3(0.0, 1.2, 4.0)]:
		var pair: Array = _reflection_uv_pair(mirror, point)
		assert_almost_eq((pair[1] as Vector2).y, (pair[0] as Vector2).y, FLIP_TOLERANCE,
			"%v lands at the wrong height in the reflection" % point)

func test_the_reflection_is_flipped_exactly_as_the_shader_expects() -> void:
	var mirror: Mirror = await _lab_mirror()
	for point in [Vector3(-4.6, 1.1, -1.4), Vector3(4.2, 1.6, -2.0)]:
		var pair: Array = _reflection_uv_pair(mirror, point)
		var expected: Vector2 = pair[0]
		var actual: Vector2 = pair[1]
		assert_almost_eq(actual.x, 1.0 - expected.x, FLIP_TOLERANCE,
			("%v is at u=%.4f in the reflection; a real mirror puts it at %.4f, so the shader's " 			+ "1.0 - SCREEN_UV.x expects %.4f. The two halves have drifted apart.") 				% [point, actual.x, expected.x, 1.0 - expected.x])
