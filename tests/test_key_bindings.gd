extends ParkourTest

# Player-rebindable controls: the binding table (InputBindings), the keyboard
# source reading through it, the names prompts show, the store round-trip, and
# the player's event-driven actions. The settings page is
# test_key_binding_settings.gd. Structure only -- which key
# an action defaults to is asserted once, as "the defaults play exactly as the
# hard-coded keys did".

const TestWorld = preload("res://tests/world_fixture.gd")

## A keyboard source with the hardware stood in for: a headless run can neither
## hold a key nor capture the mouse.
class FakeSource extends KeyboardInputSource:
	var keys: Dictionary = {}
	var buttons: Dictionary = {}
	var captured := true
	func _is_captured() -> bool:
		return captured
	func _key_down(code: int) -> bool:
		return keys.has(code)
	func _button_down(button: int) -> bool:
		return buttons.has(button)

## The keyboard source as it was before bindings existed, constants and all,
## reading the same fake hardware. What the defaults must reproduce.
class LegacySource extends RefCounted:
	var fake: FakeSource
	var _jump_was_held := false
	var _crouch_was_held := false
	var _turn_was_held := false
	var _melee_was_held := false
	func poll() -> MoveInput:
		var out := MoveInput.new()
		var forward := 0.0
		if fake._key_down(KEY_W):
			forward += 1.0
		if fake._key_down(KEY_S):
			forward -= 1.0
		var strafe := 0.0
		if fake._key_down(KEY_D):
			strafe += 1.0
		if fake._key_down(KEY_A):
			strafe -= 1.0
		out.move = Vector2(strafe, forward)
		if out.move.length_squared() > 1.0:
			out.move = out.move.normalized()
		out.strafe_axis = strafe
		out.raw_move = Vector2(strafe, forward)
		var jump_held := fake._key_down(KEY_SPACE)
		out.jump_pressed = jump_held and not _jump_was_held
		out.jump_held = jump_held
		_jump_was_held = jump_held
		out.walk_held = fake._key_down(KEY_CTRL)
		var crouch_held := fake._key_down(KEY_SHIFT)
		out.crouch_held = crouch_held
		out.crouch_pressed = crouch_held and not _crouch_was_held
		_crouch_was_held = crouch_held
		var turn_held := fake._key_down(KEY_Q)
		out.turn_pressed = turn_held and not _turn_was_held
		_turn_was_held = turn_held
		var melee_held := fake._button_down(MOUSE_BUTTON_LEFT)
		out.melee_pressed = melee_held and not _melee_was_held
		_melee_was_held = melee_held
		return out

var _test_settings_path: String
var _real_settings_path: String
var _real_bindings: Dictionary
var _real_prefs: String
var _world: Dictionary = {}

func before_all() -> void:
	_test_settings_path = "user://settings_bindings_test_%d.cfg" % OS.get_process_id()
	_real_settings_path = SettingsStore.path
	SettingsStore.path = _test_settings_path
	_real_bindings = InputBindings.current().duplicate(true)
	_real_prefs = CameraRig.prefs_path
	CameraRig.prefs_path = "user://camera_prefs_bindings_test_%d.cfg" % OS.get_process_id()

func after_all() -> void:
	_delete(SettingsStore.path)
	SettingsStore.path = _real_settings_path
	InputBindings.use(_real_bindings)
	_delete(CameraRig.prefs_path)
	CameraRig.prefs_path = _real_prefs

func before_each() -> void:
	_delete(SettingsStore.path)
	InputBindings.use(InputBindings.defaults())

func after_each() -> void:
	_delete(SettingsStore.path)
	InputBindings.use(InputBindings.defaults())
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _notch(source: KeyboardInputSource, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	source.accumulate_press(event)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	source.accumulate_press(release)

func _key_event(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _bindings_with(action: String, slots: Array) -> Dictionary:
	var table := InputBindings.defaults()
	while slots.size() < InputBindings.SLOTS:
		slots.append({})
	table[action] = slots
	return table

# ---------------------------------------------------------------------------
# KeyboardInputSource through the table
# ---------------------------------------------------------------------------

func test_the_default_bindings_play_exactly_as_the_hard_coded_keys_did() -> void:
	var source := FakeSource.new()
	var legacy := LegacySource.new()
	legacy.fake = source
	# Each step is what is held on that poll; held across steps is what
	# exercises the edges.
	var steps: Array = [
		{keys = [], buttons = []},
		{keys = [KEY_W], buttons = []},
		{keys = [KEY_W, KEY_A], buttons = []},
		{keys = [KEY_W, KEY_A, KEY_SPACE], buttons = []},
		{keys = [KEY_W, KEY_SPACE, KEY_SHIFT], buttons = []},
		{keys = [KEY_S, KEY_D, KEY_SHIFT, KEY_CTRL], buttons = []},
		{keys = [KEY_Q], buttons = [MOUSE_BUTTON_LEFT]},
		{keys = [KEY_Q, KEY_SPACE], buttons = [MOUSE_BUTTON_LEFT]},
		{keys = [KEY_A, KEY_D, KEY_W, KEY_S], buttons = []},
		{keys = [KEY_SPACE, KEY_Q, KEY_SHIFT], buttons = [MOUSE_BUTTON_LEFT]},
		{keys = [], buttons = []},
	]
	var fields := ["move", "strafe_axis", "raw_move", "jump_pressed", "jump_held",
		"walk_held", "crouch_held", "crouch_pressed", "turn_pressed", "melee_pressed"]
	for i in steps.size():
		source.keys.clear()
		source.buttons.clear()
		for code in steps[i].keys:
			source.keys[code] = true
		for button in steps[i].buttons:
			source.buttons[button] = true
		var got := source.poll()
		var want := legacy.poll()
		for field in fields:
			assert_eq(got.get(field), want.get(field),
				"step %d: %s differs from the hard-coded keys" % [i, field])

func test_a_rebound_key_drives_its_action_and_the_old_key_no_longer_does() -> void:
	InputBindings.use(_bindings_with(InputBindings.JUMP, [InputBindings.key(KEY_E)]))
	var source := FakeSource.new()
	source.keys[KEY_SPACE] = true
	var input := source.poll()
	assert_false(input.jump_pressed or input.jump_held, "the old jump key still jumps")
	source.keys.clear()
	source.keys[KEY_E] = true
	input = source.poll()
	assert_true(input.jump_pressed, "the new jump key does not press jump")
	assert_true(input.jump_held, "the new jump key does not hold jump")

func test_a_mouse_button_binding_is_polled_like_a_key() -> void:
	InputBindings.use(_bindings_with(InputBindings.CROUCH, [InputBindings.mouse(MOUSE_BUTTON_XBUTTON1)]))
	var source := FakeSource.new()
	source.buttons[MOUSE_BUTTON_XBUTTON1] = true
	var first := source.poll()
	var second := source.poll()
	assert_true(first.crouch_pressed and first.crouch_held, "a held side button does not crouch")
	assert_true(second.crouch_held and not second.crouch_pressed, "a held side button pressed twice")

func test_a_wheel_notch_on_jump_is_one_press_held_for_exactly_one_poll() -> void:
	InputBindings.use(_bindings_with(InputBindings.JUMP, [InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)]))
	var source := FakeSource.new()
	_notch(source, MOUSE_BUTTON_WHEEL_UP)
	var on := source.poll()
	assert_true(on.jump_pressed, "the poll after a notch has no jump press")
	assert_true(on.jump_held, "the notch is not held for its poll")
	var off := source.poll()
	assert_false(off.jump_pressed, "one notch pressed jump twice")
	assert_false(off.jump_held, "the notch is still held on the following poll")

func test_a_notch_every_tick_is_a_press_every_tick() -> void:
	InputBindings.use(_bindings_with(InputBindings.JUMP, [InputBindings.mouse(MOUSE_BUTTON_WHEEL_DOWN)]))
	var source := FakeSource.new()
	for i in 4:
		_notch(source, MOUSE_BUTTON_WHEEL_DOWN)
		var input := source.poll()
		assert_true(input.jump_pressed, "tick %d: a notch on a consecutive tick is not a press" % i)

func test_several_notches_inside_one_tick_are_one_press() -> void:
	InputBindings.use(_bindings_with(InputBindings.JUMP, [InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)]))
	var source := FakeSource.new()
	for i in 3:
		_notch(source, MOUSE_BUTTON_WHEEL_UP)
	assert_true(source.poll().jump_pressed, "three notches gave no press")
	assert_false(source.poll().jump_pressed, "notches carried over into the next tick")

func test_a_notch_does_not_hide_the_next_key_press() -> void:
	InputBindings.use(_bindings_with(InputBindings.JUMP,
		[InputBindings.key(KEY_SPACE), InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)]))
	var source := FakeSource.new()
	_notch(source, MOUSE_BUTTON_WHEEL_UP)
	source.poll()
	source.keys[KEY_SPACE] = true
	assert_true(source.poll().jump_pressed, "a key press right after a notch was not a press")

func test_a_wheel_nothing_is_bound_to_does_nothing() -> void:
	var source := FakeSource.new()
	_notch(source, MOUSE_BUTTON_WHEEL_UP)
	var input := source.poll()
	assert_false(input.jump_pressed or input.crouch_pressed or input.turn_pressed or input.melee_pressed,
		"an unbound wheel notch pressed something")

func test_nothing_is_read_while_the_mouse_is_not_captured() -> void:
	InputBindings.use(_bindings_with(InputBindings.JUMP,
		[InputBindings.key(KEY_SPACE), InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)]))
	var source := FakeSource.new()
	source.captured = false
	source.keys[KEY_W] = true
	source.keys[KEY_SPACE] = true
	source.accumulate_look(Vector2(30.0, 0.0))
	_notch(source, MOUSE_BUTTON_WHEEL_UP)
	var released := source.poll()
	assert_eq(released.move, Vector2.ZERO, "a key moved the body with the mouse released")
	assert_false(released.jump_pressed or released.jump_held, "jump was read with the mouse released")
	assert_eq(released.look, Vector2.ZERO, "look was read with the mouse released")

	# Recaptured with the key still down: no fresh press, and the notch taken
	# while released is gone.
	source.captured = true
	var recaptured := source.poll()
	assert_false(recaptured.jump_pressed, "a jump held across the recapture read as a fresh press")
	assert_true(recaptured.jump_held, "the held jump key is not held after the recapture")
	source.keys.erase(KEY_SPACE)
	assert_false(source.poll().jump_held, "a notch taken while released survived into the game")

# The press latch: a press the poll never saw down is still a press.

func test_a_key_tapped_between_two_polls_is_exactly_one_press() -> void:
	var source := FakeSource.new()
	source.poll()
	source.accumulate_press(_key_event(KEY_SPACE))
	source.accumulate_press(_key_event(KEY_SPACE, false))
	var on := source.poll()
	assert_true(on.jump_pressed, "a tap inside one tick was lost")
	assert_true(on.jump_held, "a tap inside one tick is not held for its poll")
	var off := source.poll()
	assert_false(off.jump_pressed, "one tap pressed jump twice")
	assert_false(off.jump_held, "the tap is still held on the following poll")

func test_a_press_arriving_after_this_tick_s_poll_lands_on_the_next_one() -> void:
	var source := FakeSource.new()
	assert_false(source.poll().turn_pressed, "turn pressed with nothing down")
	# Same frame, after _physics_process: the key goes down and stays down.
	source.accumulate_press(_key_event(KEY_Q))
	source.keys[KEY_Q] = true
	assert_true(source.poll().turn_pressed, "a press arriving after the poll was lost")
	assert_false(source.poll().turn_pressed, "the held key pressed turn a second time")

func test_a_release_and_re_press_inside_one_tick_is_a_press() -> void:
	var source := FakeSource.new()
	source.keys[KEY_SPACE] = true
	assert_true(source.poll().jump_pressed, "the first press was lost")
	# Down at both polls, but let go and pressed again in between.
	source.accumulate_press(_key_event(KEY_SPACE, false))
	source.accumulate_press(_key_event(KEY_SPACE))
	var again := source.poll()
	assert_true(again.jump_pressed, "a re-press inside one tick was lost")
	assert_true(again.jump_held, "the re-pressed key is not held")

func test_the_click_that_captures_the_mouse_is_not_an_attack() -> void:
	var source := FakeSource.new()
	source.captured = false
	source.poll()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	# Player latches in _input, before its _unhandled_input captures the mouse.
	source.accumulate_press(click)
	source.captured = true
	source.buttons[MOUSE_BUTTON_LEFT] = true
	assert_false(source.poll().melee_pressed, "the capturing click read as an attack")
	source.buttons.clear()
	source.accumulate_press(click)
	assert_true(source.poll().melee_pressed, "the next click, captured, is not an attack")

func test_a_press_after_the_capture_is_not_swallowed_by_the_resync() -> void:
	var source := FakeSource.new()
	source.captured = false
	source.poll()
	source.captured = true
	source.accumulate_press(_key_event(KEY_SPACE))
	source.accumulate_press(_key_event(KEY_SPACE, false))
	assert_true(source.poll().jump_pressed, "a press between the capture and the first poll was lost")

# ---------------------------------------------------------------------------
# Names and the store
# ---------------------------------------------------------------------------

func test_input_names_name_the_current_binding() -> void:
	assert_eq(InputNames.label(InputNames.MOVE), "WASD", "the default movement keys are not named WASD")
	InputBindings.use(_bindings_with(InputBindings.JUMP, [InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)]))
	assert_eq(InputNames.label(InputNames.JUMP), "滚轮上", "a prompt still names the old jump key")
	InputBindings.use(_bindings_with(InputBindings.MELEE, [{}, InputBindings.key(KEY_F)]))
	assert_eq(InputNames.label(InputNames.MELEE), "F", "an empty primary slot hid the secondary's name")

func test_bindings_round_trip_through_the_store() -> void:
	var saved := SettingsStore.defaults()
	saved.bindings[InputBindings.JUMP] = [InputBindings.key(KEY_SPACE), InputBindings.mouse(MOUSE_BUTTON_WHEEL_DOWN)]
	saved.bindings[InputBindings.ZOOM_OUT] = [{}, {}]
	saved.bindings[InputBindings.TURN] = [InputBindings.mouse(MOUSE_BUTTON_XBUTTON2), InputBindings.key(KEY_E)]
	SettingsStore.save_settings(saved)
	var loaded := SettingsStore.load_settings()
	assert_eq(loaded.bindings, saved.bindings, "the bindings did not round-trip")

func test_an_older_file_without_an_action_gets_its_default() -> void:
	var saved := SettingsStore.defaults()
	saved.bindings.erase(InputBindings.FRAME_CAMERA)
	saved.bindings[InputBindings.JUMP] = ["garbage", 7]
	SettingsStore.save_settings(saved)
	var loaded := SettingsStore.load_settings()
	assert_eq(loaded.bindings[InputBindings.FRAME_CAMERA],
		InputBindings.defaults()[InputBindings.FRAME_CAMERA], "a missing action did not take its default")
	assert_eq(loaded.bindings[InputBindings.JUMP], [{}, {}], "malformed slots were not emptied")

# ---------------------------------------------------------------------------
# The player's event-driven actions
# ---------------------------------------------------------------------------

func test_a_rebound_view_key_toggles_the_view_and_v_no_longer_does() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	var player: Player = _world["player"]
	InputBindings.use(_bindings_with(InputBindings.TOGGLE_VIEW, [InputBindings.key(KEY_G)]))
	var before := player.camera_rig.in_third_person()
	player._unhandled_input(_key_event(KEY_V))
	assert_eq(player.camera_rig.in_third_person(), before, "V still toggles the view")
	player._unhandled_input(_key_event(KEY_G))
	assert_ne(player.camera_rig.in_third_person(), before, "the rebound key does not toggle the view")

func test_a_wheel_taken_by_jump_no_longer_zooms() -> void:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	var player: Player = _world["player"]
	if not player.camera_rig.in_third_person():
		player.camera_rig.toggle_third_person()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	assert_true(player._handle_third_person_input(wheel), "the default wheel does not zoom")
	var table := InputBindings.defaults()
	table[InputBindings.ZOOM_IN] = [{}, {}]
	table[InputBindings.JUMP] = [InputBindings.key(KEY_SPACE), InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)]
	InputBindings.use(table)
	assert_false(player._handle_third_person_input(wheel), "the wheel zooms after jump took it")
