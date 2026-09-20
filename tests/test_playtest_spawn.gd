extends ParkourTest

# "Play from here": the editor leaves a note, the run puts the body there in
# noclip, and the note is spent. What matters is that it fires ONCE and never
# hijacks an ordinary run.

const Spawn := preload("res://scripts/debug/playtest_spawn.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Spawn.NOTE))

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	return _world["player"]

func _note(position: Vector3, yaw: float, age_seconds: float = 0.0) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("at", "position", position)
	cfg.set_value("at", "yaw", yaw)
	cfg.set_value("at", "unix_time", Time.get_unix_time_from_system() - age_seconds)
	cfg.save(Spawn.NOTE)

func test_the_body_lands_where_the_note_says_and_flies() -> void:
	var player: Player = await _player()
	assert_false(player.noclip, "test setup: noclip was already on")
	var spawn := Spawn.new()
	add_child_autofree(spawn)
	await spawn._place(Vector3(12.0, 30.0, -4.0), deg_to_rad(90.0))
	assert_almost_eq(player.global_position, Vector3(12.0, 30.0, -4.0), Vector3.ONE * 0.01,
		"the body did not land where the note said")
	assert_true(player.noclip, "dropped in mid-air without noclip, which is a death sentence")

func test_a_stale_note_is_ignored() -> void:
	# The editor wrote it for a run that never happened; an ordinary run
	# afterwards must start where the level says.
	var player: Player = await _player()
	var before := player.global_position
	_note(Vector3(50.0, 50.0, 50.0), 0.0, Spawn.FRESH_FOR_SECONDS + 10.0)
	var spawn := Spawn.new()
	add_child_autofree(spawn)
	await step(3)
	assert_almost_eq(player.global_position, before, Vector3.ONE * 0.5,
		"a stale note moved the body anyway")

func test_the_note_is_spent_when_it_is_read() -> void:
	# Once used it must not fire again on the next run.
	_note(Vector3(1.0, 2.0, 3.0), 0.0)
	var spawn := Spawn.new()
	add_child_autofree(spawn)
	await step(3)
	assert_false(FileAccess.file_exists(Spawn.NOTE), "the note survived its own run")
