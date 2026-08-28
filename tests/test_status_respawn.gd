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
