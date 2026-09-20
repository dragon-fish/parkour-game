extends ParkourTest

# What the original bolts to a moving actor is the whole of what that actor
# does to the player: a train's cars have no collision, and the kill box, the
# horn box and the shake cylinder ride along. A rider that does not travel is
# a hazard standing still in a place the original has none.
#
# Structural only. How hard the camera shakes and how loud the horn is are
# dials -- see .claude/skills/tuning-dials-not-rules.

const GAP_MIN := 5.0
const GAP_MAX := 10.0

## A mover with one Area3D riding it, keyed to slide 4 m along -Z. `pivots`
## carries the mover's own frame, which is how the builder hands a Matinee
## something that is not the driven actor itself.
func _rig(looping: bool) -> Dictionary:
	var root := Node3D.new()
	var mover := Node3D.new()
	mover.name = "Mover"
	mover.position = Vector3(10.0, 0.0, 0.0)
	root.add_child(mover)
	var rider := Area3D.new()
	rider.name = "Rider"
	rider.position = Vector3(10.0, 0.0, 2.0)
	root.add_child(rider)
	var matinee := Matinee.new()
	matinee.name = "Run"
	matinee.length = 0.1
	matinee.autostart = looping
	var pivot := Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 0.0))
	matinee.tracks = [{
		targets = [NodePath("../Mover"), NodePath("../Rider")],
		pivots = [null, pivot],
		local = false,
		pos_times = PackedFloat32Array([0.0, 0.1]),
		pos_values = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -4.0)]),
		pos_arrive = PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		pos_leave = PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		pos_modes = PackedByteArray([1, 1]),
		rot_times = PackedFloat32Array(), rot_values = PackedVector3Array(),
		rot_arrive = PackedVector3Array(), rot_leave = PackedVector3Array(),
		rot_modes = PackedByteArray(),
		scl_times = PackedFloat32Array(), scl_values = PackedVector3Array(),
		scl_arrive = PackedVector3Array(), scl_leave = PackedVector3Array(),
		scl_modes = PackedByteArray(),
	}]
	if looping:
		matinee.followers = [{path = NodePath("../Run"), action = "play",
			delay = 7.5, delay_min = GAP_MIN, delay_max = GAP_MAX}]
	root.add_child(matinee)
	get_tree().root.add_child(root)
	return {root = root, mover = mover, rider = rider, matinee = matinee}

func test_a_volume_bolted_to_a_mover_travels_with_it_and_comes_back_on_respawn() -> void:
	var rig := _rig(false)
	await step(1)
	var mover_home: Vector3 = rig.mover.global_position
	var rider_home: Vector3 = rig.rider.global_position
	rig.matinee.play()
	await step(12)
	assert_almost_eq(rig.mover.global_position.z, mover_home.z - 4.0, 0.01,
			"the sequence did not carry the actor it drives")
	assert_almost_eq(rig.rider.global_position.z, rider_home.z - 4.0, 0.01,
			"the volume riding the actor stayed behind")
	# Its offset from what it rides is the whole point: a kill box that drifts
	# off its train stops covering the cars.
	assert_almost_eq(rig.rider.global_position.x, rig.mover.global_position.x, 0.001,
			"the rider drifted sideways off what it rides")
	get_tree().call_group(Arena.RESET_ON_RESPAWN, "reset_for_respawn")
	assert_almost_eq(rig.rider.global_position.z, rider_home.z, 0.001,
			"a respawn left the rider where the sequence put it")
	rig.root.queue_free()
	await step(1)

func test_a_self_looping_sequence_starts_itself_and_survives_a_respawn() -> void:
	var rig := _rig(true)
	await step(3)
	assert_true(rig.matinee.is_running(),
			"a sequence whose only way in is its own loop never started")
	# Dying beside the tracks must not empty them for the rest of the chapter.
	get_tree().call_group(Arena.RESET_ON_RESPAWN, "reset_for_respawn")
	await step(3)
	assert_true(rig.matinee.is_running(), "the loop did not restart after a respawn")
	rig.root.queue_free()
	await step(1)

func test_the_loop_comes_back_round_and_carries_the_rider_again() -> void:
	var rig := _rig(true)
	# A gap short enough to watch. The range is exercised separately below.
	var quick: Array[Dictionary] = [{path = NodePath("../Run"), action = "play", delay = 0.05}]
	rig.matinee.followers = quick
	await step(1)
	var rider_home: Vector3 = rig.rider.global_position
	# Long enough for a 0.1 s run, the 0.05 s gap, and the next run to begin.
	await step(14)
	assert_true(rig.matinee.is_running(), "the sequence did not start itself a second time")
	# AND it must start from the top, not from where the last run left off: the
	# keys are relative to a transform captured once, so a loop that failed to
	# rewind would walk the train one run further down the track every time.
	await step(8)
	assert_lt(rig.rider.global_position.z, rider_home.z,
			"the rider is not travelling on the second run")
	assert_gt(rig.rider.global_position.z, rider_home.z - 8.0,
			"the loop drifted past one run's worth: it did not rewind")
	rig.root.queue_free()
	await step(1)

func test_a_follower_carrying_a_range_draws_a_fresh_gap_inside_it() -> void:
	var follower := {path = NodePath("../Run"), action = "play", delay = 7.5,
		delay_min = GAP_MIN, delay_max = GAP_MAX}
	var seen := {}
	for i in 40:
		var gap := Matinee.gap_of(follower)
		assert_between(gap, GAP_MIN, GAP_MAX, "a drawn gap fell outside the original's range")
		seen[gap] = true
	# A constant gap makes a metronome of a level; the original never does.
	assert_gt(seen.size(), 1, "every gap came out the same: the range is not being drawn from")
	assert_eq(Matinee.gap_of({path = NodePath("../Run"), action = "play", delay = 2.0}), 2.0,
			"a follower with no range should keep its fixed delay")
