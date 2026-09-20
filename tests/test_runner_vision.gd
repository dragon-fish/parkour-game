extends GutTest

# RunnerVisionTarget's rules, not its look: what lights up, when, and that the
# fade is slow in and fast out. The colour and the exact distances are dials.

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


## A box with a target under it, at the origin.
func _target(distance_m: float = 15.0) -> RunnerVisionTarget:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	_root.add_child(mesh)
	var target := RunnerVisionTarget.new()
	target.distance_m = distance_m
	mesh.add_child(target)
	return target


func test_a_target_paints_the_mesh_it_stands_under() -> void:
	var target := _target()
	var mesh := target.get_parent() as MeshInstance3D
	assert_eq(target.advance(0.0, Vector3(500.0, 0.0, 0.0)), 0.0, "lit with the player nowhere near")
	target.advance(1.0, Vector3.ZERO)
	assert_not_null(mesh.material_overlay, "standing on the target did not paint the mesh")
	assert_gt(target.advance(0.0, Vector3.ZERO), 0.0, "standing on the target did not light it")

func test_out_of_range_stays_dark() -> void:
	var target := _target(5.0)
	for i in 10:
		target.advance(0.1, Vector3(9.0, 0.0, 0.0))
	assert_eq(target.advance(0.1, Vector3(9.0, 0.0, 0.0)), 0.0, "lit from outside its distance")

func test_it_fades_in_over_about_a_second() -> void:
	# [ME:CONFIRMED] FadeInSpeed 1.0: a second from nothing to painted.
	var target := _target()
	var strength := 0.0
	for i in 30:
		strength = target.advance(1.0 / 60.0, Vector3.ZERO)
	assert_almost_eq(strength, 0.5, 0.05, "half a second in, strength is %.2f" % strength)

func test_it_fades_out_four_times_faster_than_in() -> void:
	# The hint arrives before the decision and is gone by the time the move is
	# under way -- 1.0 in against 4.0 out.
	var target := _target(5.0)
	for i in 120:
		target.advance(1.0 / 60.0, Vector3.ZERO)
	var far := Vector3(50.0, 0.0, 0.0)
	var ticks := 0
	while target.advance(1.0 / 60.0, far) > 0.0 and ticks < 600:
		ticks += 1
	assert_almost_eq(ticks / 60.0, 0.25, 0.05, "took %.2f s to fade out" % (ticks / 60.0))

func test_the_proximity_delay_holds_it_back() -> void:
	# [ME:CONFIRMED] LOIProximityDelay: near is not yet lit.
	var target := _target()
	target.proximity_delay = 1.0
	for i in 30:
		assert_eq(target.advance(1.0 / 60.0, Vector3.ZERO), 0.0, "lit before its delay elapsed")
	for i in 60:
		target.advance(1.0 / 60.0, Vector3.ZERO)
	assert_gt(target.advance(1.0 / 60.0, Vector3.ZERO), 0.0, "never lit after its delay")

func test_it_stays_lit_for_its_minimum() -> void:
	# A hint that blinks as the player strafes past its edge is worse than one
	# that stays a moment too long.
	var target := _target(5.0)
	target.min_duration = 1.0
	target.advance(1.0 / 60.0, Vector3.ZERO)
	var far := Vector3(50.0, 0.0, 0.0)
	for i in 30:
		target.advance(1.0 / 60.0, far)
	assert_gt(target.advance(1.0 / 60.0, far), 0.0, "went dark inside its minimum duration")

func test_flat_distance_ignores_height() -> void:
	# [ME:CONFIRMED] LOIUse2DDistance: a pipe two floors up is as near as the
	# floor it hangs over.
	var above := Vector3(0.0, 40.0, 0.0)
	var upright := _target(10.0)
	assert_eq(upright.advance(1.0, above), 0.0, "height counted as no distance at all")
	var flat := _target(10.0)
	flat.flat_distance = true
	assert_gt(flat.advance(1.0, above), 0.0, "flat distance still counted the height")

func test_a_target_over_nothing_says_so() -> void:
	var orphan := RunnerVisionTarget.new()
	_root.add_child(orphan)
	assert_gt(orphan._get_configuration_warnings().size(), 0,
		"a target painting nothing gave no warning")
