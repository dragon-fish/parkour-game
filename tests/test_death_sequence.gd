class_name TestDeathSequence
extends TestCase

# Death is NOT a Move (spec §1): PlayerDying appears once in the whole CDO
# library, on FallingUncontrolled itself, and no Move succeeds it on landing.
# The sequence therefore belongs to the level, and this test pins that
# ownership -- if it ever needs a Move to run, the design drifted.

func test_the_sequence_reports_its_own_duration() -> void:
	var seq := DeathSequence.new()
	tree.root.add_child(seq)
	await step(1)
	check_greater(seq.total_duration(), 1.0, "the death sequence is too short to read")
	check_greater(3.0, seq.total_duration(), "the death sequence outstays its welcome")
	seq.queue_free()
	await step(1)

func test_it_finishes_and_says_so() -> void:
	var seq := DeathSequence.new()
	tree.root.add_child(seq)
	await step(1)
	var done := {"hit": false}
	seq.finished.connect(func() -> void: done["hit"] = true)
	seq.play(null)
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 20
	for i in ticks:
		await step(1)
		if done["hit"]:
			break
	check(done["hit"], "the death sequence never finished")
	seq.queue_free()
	await step(1)
