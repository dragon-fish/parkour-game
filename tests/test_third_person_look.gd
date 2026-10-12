extends ParkourTest

# What the third-person camera keeps for the player through the ported moves.
# The original has no third person: its rules for the view are written for the
# first-person eye, and the orbit camera is this project's own.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}
	await step(1)

func _player(third: bool) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.camera_rig.third_person = third
	await step(1)
	return player

## A move's look-input ignore (a roll, a vault, a hard landing's hold) holds
## the first-person eye still; in third person the orbit stays the player's.
func test_a_look_ignore_holds_the_eye_but_not_the_orbit() -> void:
	for third in [false, true]:
		var player: Player = await _player(third)
		var input: ScriptedInputSource = _world["input"]
		player.set_ignore_look_input(-1.0)
		var before: float = player.rotation.y
		for i in 10:
			input.state.look = Vector2(-20.0, 0.0)
			await step(1)
		input.state.look = Vector2.ZERO
		player.stop_ignore_look_input()
		var turned: float = absf(wrapf(player.rotation.y - before, -PI, PI))
		if third:
			assert_gt(turned, deg_to_rad(5.0), "the ignore froze the third-person orbit")
		else:
			assert_almost_eq(turned, 0.0, 0.0001, "the ignore let the first-person eye turn")
		TestWorld.teardown(_world)
		_world = {}
		await step(1)
