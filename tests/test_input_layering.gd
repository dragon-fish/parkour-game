extends ParkourTest

# Mouse BUTTONS belong behind the GUI. Player handled buttons in _input(),
# which runs BEFORE the GUI gets to consume anything -- so a click aimed at
# an F1-panel slider, or a scroll meant to zoom the panel, also reached the
# game underneath it (camera recapture, third-person distance zoom). The
# game's share of the mouse is whatever the Controls leave over:
# _unhandled_input.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func test_buttons_are_left_for_the_gui_layer() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(5)
	var player: Player = _world["player"]
	player.camera_rig.toggle_third_person()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	# _input runs before the GUI: a button arriving here must be IGNORED, or
	# the panel can never own a click.
	player._input(press)
	assert_false(player._framing_drag, \
		"_input() still grabs mouse buttons ahead of the GUI")
	# The same event surviving to _unhandled_input is the game's to take.
	player._unhandled_input(press)
	assert_true(player._framing_drag, \
		"the game layer stopped handling buttons entirely")
