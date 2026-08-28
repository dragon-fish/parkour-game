extends ParkourTest

# The opening level puts INF statuses on a volume that covers the spawn. That
# shape is what these tests are about: a body that respawns INSIDE a volume
# never left it, so body_entered will not fire again on its own.

func _arena() -> Arena:
	var a: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(a)
	return a

func _cap(scale: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = INF
	return s

func test_a_respawn_clears_every_status() -> void:
	var a := _arena()
	await step(2)
	a.player.statuses.apply(_cap(0.5), a.player, 0)
	a.reset_player()
	await step(2)
	assert_false(a.player.statuses.has(Status.Effect.SPEED_CAP), \
		"a status survived the respawn")

func test_a_respawn_re_arms_a_capped_volume() -> void:
	var a := _arena()
	await step(2)
	var v := ModifierVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box
	v.add_child(shape)
	v.apply = [_cap(0.5)]
	v.max_trigger_count = 1
	a.add_child(v)
	v.global_position = a.spawn_point.global_position
	await step(5)
	assert_true(a.player.statuses.has(Status.Effect.SPEED_CAP), "the fixture never applied")
	a.reset_player()
	await step(5)
	assert_true(a.player.statuses.has(Status.Effect.SPEED_CAP), \
		"the player woke up cured: the count was not reset, or the overlap was not re-applied")

func test_a_respawn_outside_the_volume_does_not_carry_its_status_back() -> void:
	# The mirror of the test above, and the one that pins WHERE the overlap
	# query may run. Area3D rebuilds its overlap list once per physics frame,
	# before that frame's physics step -- asked between the teleport and the
	# next step it still names the volume the body DIED in. Nothing tracks
	# membership here by design, so an INF status re-applied to a body that
	# respawned outside would never be taken off again.
	var a := _arena()
	await step(1)
	# Settled on the floor before the box is built around it: a capsule still
	# being pushed out of the floor slab can drift out of a volume placed on
	# its unsettled position. Far enough from spawn that the 6 m box cannot
	# reach it -- the respawn must land OUTSIDE.
	a.player.global_position = a.spawn_point.global_position + Vector3(0.0, 0.0, 25.0)
	await step(30)
	var v := ModifierVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box
	v.add_child(shape)
	v.apply = [_cap(0.5)]
	a.add_child(v)
	v.global_position = a.player.global_position
	await step(5)
	assert_true(a.player.statuses.has(Status.Effect.SPEED_CAP), "the fixture never applied")
	a.reset_player()
	await step(5)
	assert_false(a.player.statuses.has(Status.Effect.SPEED_CAP), \
		"a volume the body respawned OUTSIDE of put its status back")
