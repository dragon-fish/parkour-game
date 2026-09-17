extends ParkourTest

# A lethal volume is a DEATH, not a teleport. What it saves the player is the
# fall -- a lift shaft kills at the top instead of fifteen seconds later -- and
# the four seconds of dying afterwards are the same four every other death
# costs. The volume's other use needs them: a boundary at a junction, dressed
# with guards, where the fiction is being shot.
#
# Which curtain a respawn draws is the one thing the player reads it by: black
# is a death, white is a reset they asked for. The colours are tuning; that the
# two paths draw DIFFERENT ones, and that neither can loop, is not.

## The death sequence (4.0 s) plus its post-respawn cover (0.75 s), with room
## to spare. Deliberately generous: this is a "by now, surely" bound, not a
## measurement of the timings, which are the owner's to re-dial.
const RIGHT_THROUGH := 320

func _arena() -> Arena:
	var a: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(a)
	return a

func _lethal_at(arena: Arena, at: Vector3) -> DeathVolume:
	var volume := DeathVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box
	volume.add_child(shape)
	arena.add_child(volume)
	volume.global_position = at
	return volume

func test_walking_into_a_lethal_volume_respawns_the_player() -> void:
	var arena := _arena()
	await step(2)
	var spawn: Vector3 = arena.spawn_point.global_position
	_lethal_at(arena, spawn + Vector3(40.0, 0.0, 0.0))
	arena.player.global_position = spawn + Vector3(40.0, 0.0, 0.0)
	await step(RIGHT_THROUGH)
	assert_lt(arena.player.global_position.distance_to(spawn), 3.0, \
		"the body was left in the volume that was supposed to kill it")

func test_a_lethal_volume_performs_a_death_rather_than_cutting_to_black() -> void:
	# The misreading this exists to prevent: taking "the shaft saves fifteen
	# seconds" to mean the dying should be skipped too.
	var arena := _arena()
	await step(2)
	_lethal_at(arena, arena.player.global_position)
	await step(4)
	assert_true(arena.player.is_dying(), \
		"touching a lethal volume respawned the body without dying first")

func test_a_volume_death_is_not_a_fall_death() -> void:
	# [ME:CONFIRMED] The original has ONE death animation and it is the
	# non-fall one. The falling performance is this project's addition, so the
	# animator has to be able to tell them apart -- and it cannot ask the move
	# name, because a fatal landing hands the machine back to WALKING first.
	var arena := _arena()
	await step(2)
	_lethal_at(arena, arena.player.global_position)
	await step(4)
	assert_eq(arena.player.health.last_cause, Health.Cause.VOLUME, \
		"a volume death would play the falling clip")

func test_a_lethal_volume_around_the_spawn_does_not_loop() -> void:
	# An author who drops a shaft over a checkpoint should get a stuck player,
	# not a hung game. Two separate things keep it from looping and only one of
	# them is the guard: a body that respawns INSIDE the volume never left it,
	# so Area3D has no entry to report. It dies once and then stands there.
	var arena := _arena()
	await step(2)
	_lethal_at(arena, arena.spawn_point.global_position)
	await step(4)
	assert_true(arena.player.is_dying(), "test setup: the volume never fired")
	await step(RIGHT_THROUGH)
	assert_true(is_instance_valid(arena.player), "the loop took the player with it")
	assert_false(arena.player.is_dying(), \
		"the death never ended: something is starting a fresh one every frame")

func test_falling_out_of_the_world_is_a_death_and_a_reset_is_not() -> void:
	# The net under the level is the one death with nothing to perform: the
	# body is in the void, there is no floor to give way onto, and it only
	# fires at all when the level failed to mark its own boundary. So it keeps
	# the plain curtain -- black, because it is still a death.
	var arena := _arena()
	await step(2)
	arena.player.global_position = Vector3(0.0, arena.fall_out_height - 5.0, 0.0)
	await step(2)
	assert_true(arena._death_sequence.is_covering(), \
		"falling out of the world still teleported the body with no curtain")
	assert_eq(arena.player.screen_effects.tint_color(), Color.BLACK, \
		"falling out of the world did not read as a death")

# A body is what makes the forced view necessary and is also what gates it, so
# these two need one mounted. The repo ships no character model -- a bare node
# is enough, because nothing here looks inside it.
##
## The view is SET rather than assumed: CameraRig loads the machine's saved
## preference on setup, so whether an Arena starts in first person is a fact
## about whoever ran the suite last.
func _in_first_person_with_a_body(arena: Arena) -> void:
	var stand_in := Node3D.new()
	arena.player.add_child(stand_in)
	arena.player.body = stand_in
	arena.player.camera_rig.third_person = false

func test_a_non_fall_death_is_watched_from_outside_and_gives_the_view_back() -> void:
	# Death02 collapses face down: in first person the eye ends up under the
	# floor looking up through the model. Handing the view back afterwards is
	# the half that fails quietly -- a player stranded in third person would
	# find the V key doing nothing and no way to say why.
	var arena := _arena()
	await step(2)
	_in_first_person_with_a_body(arena)
	assert_false(arena.player.camera_rig.in_third_person(), \
		"test setup: this only means anything starting in first person")
	_lethal_at(arena, arena.player.global_position)
	await step(4)
	assert_true(arena.player.camera_rig.in_third_person(), \
		"the death played from inside a face-down head")
	await step(RIGHT_THROUGH)
	assert_false(arena.player.camera_rig.in_third_person(), \
		"the view never came back: the player is stranded in third person")

func test_a_fall_death_keeps_the_view_it_had() -> void:
	# The falling performance has its own camera and wants none of this. It is
	# also the death that runs most often, so a forced view here would read as
	# the game deciding how the player watches every mistake they make.
	var arena := _arena()
	await step(2)
	_in_first_person_with_a_body(arena)
	arena.player.health.last_cause = Health.Cause.FALL
	arena.player.set_dying(true)
	assert_false(arena.player.camera_rig.in_third_person(), \
		"a fall death pulled the camera out on its own")
	arena.player.set_dying(false)
