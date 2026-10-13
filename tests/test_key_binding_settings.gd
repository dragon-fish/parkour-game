extends ParkourTest

# The settings page's 按键绑定 section: capture, the conflict rule, and that a
# rebind lives in the page's working copy like every other setting -- in use
# on 保存设置, gone on 取消.

var _test_settings_path: String
var _real_settings_path: String
var _real_bindings: Dictionary

func before_all() -> void:
	_test_settings_path = "user://settings_binding_page_test_%d.cfg" % OS.get_process_id()
	_real_settings_path = SettingsStore.path
	SettingsStore.path = _test_settings_path
	_real_bindings = InputBindings.current().duplicate(true)

func after_all() -> void:
	_delete(SettingsStore.path)
	SettingsStore.path = _real_settings_path
	InputBindings.use(_real_bindings)

func before_each() -> void:
	_delete(SettingsStore.path)
	InputBindings.use(InputBindings.defaults())

func after_each() -> void:
	_delete(SettingsStore.path)
	InputBindings.use(InputBindings.defaults())

func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _key_event(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _page() -> MeSettingsMenu:
	var page := MeSettingsMenu.new()
	add_child_autofree(page)
	await step(1)
	return page

func _dialog_button(page: MeSettingsMenu, text: String) -> Button:
	assert_not_null(page._conflict_dialog, "no conflict dialog is up")
	for button in page._find_buttons(page._conflict_dialog):
		if button.text == text:
			return button
	return null

func test_capture_takes_the_next_press_and_saves_with_the_page() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 1)
	page._input(_key_event(KEY_E))
	assert_true(page._capture.is_empty(), "capture did not end on a key")
	assert_true(InputBindings.same(page._working.bindings[InputBindings.JUMP][1], InputBindings.key(KEY_E)),
		"the captured key was not put in the slot")
	assert_false(InputBindings.matches(_key_event(KEY_E), InputBindings.JUMP),
		"a rebind reached the game before 保存设置")
	page._on_save_pressed()
	assert_true(InputBindings.matches(_key_event(KEY_E), InputBindings.JUMP),
		"保存设置 did not put the rebind into use")
	assert_true(InputBindings.same(SettingsStore.load_settings().bindings[InputBindings.JUMP][1],
		InputBindings.key(KEY_E)), "保存设置 did not write the rebind")

func test_cancel_discards_an_unsaved_rebind() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 1)
	page._input(_key_event(KEY_E))
	page._on_cancel_pressed()
	assert_false(FileAccess.file_exists(SettingsStore.path), "取消 wrote settings.cfg")
	assert_false(InputBindings.matches(_key_event(KEY_E), InputBindings.JUMP), "取消 put the rebind into use")
	page.reload()
	assert_eq(page._working.bindings, InputBindings.defaults(), "the page reopened on the cancelled rebind")

func test_esc_in_capture_cancels_the_capture_and_nothing_else() -> void:
	var page: MeSettingsMenu = await _page()
	watch_signals(page)
	page._begin_capture(InputBindings.JUMP, 0)
	page._input(_key_event(KEY_ESCAPE))
	assert_true(page._capture.is_empty(), "Esc did not end the capture")
	assert_signal_not_emitted(page, "closed", "Esc in capture closed the settings page")
	assert_eq(page._working.bindings, InputBindings.defaults(), "Esc in capture changed a binding")

func test_delete_clears_the_slot_being_captured() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 0)
	page._input(_key_event(KEY_DELETE))
	assert_eq(page._working.bindings[InputBindings.JUMP][0], {}, "Delete did not clear the slot")

func test_a_wheel_notch_is_captured_and_a_reserved_key_is_not() -> void:
	var page: MeSettingsMenu = await _page()
	# Free the wheel first, so this is a plain capture and not a conflict.
	page._working.bindings[InputBindings.ZOOM_OUT] = [{}, {}]
	page._begin_capture(InputBindings.JUMP, 1)
	page._input(_key_event(KEY_R))
	assert_false(page._capture.is_empty(), "a reserved key ended the capture")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	page._input(wheel)
	assert_true(InputBindings.same(page._working.bindings[InputBindings.JUMP][1],
		InputBindings.mouse(MOUSE_BUTTON_WHEEL_DOWN)), "a wheel notch was not captured")

func test_the_same_input_in_the_other_slot_of_the_same_action_is_a_no_op() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 1)
	page._input(_key_event(KEY_SPACE))
	assert_null(page._conflict_dialog, "binding an action's own key asked about a conflict")
	assert_eq(page._working.bindings, InputBindings.defaults(), "binding an action's own key changed something")

func test_confirming_a_conflict_moves_the_binding() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 1)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	page._input(wheel)
	assert_not_null(page._conflict_dialog, "a conflicting input did not ask")
	var question: Label = page._find_first_label(page._conflict_dialog)
	assert_true(question.text.contains(InputBindings.action_label(InputBindings.ZOOM_IN)),
		"the dialog does not name the action the input is taken from")
	_dialog_button(page, "确定").pressed.emit()
	await step(1)
	assert_true(InputBindings.same(page._working.bindings[InputBindings.JUMP][1],
		InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)), "确定 did not give the input to jump")
	assert_eq(InputBindings.owner_of(page._working.bindings, InputBindings.mouse(MOUSE_BUTTON_WHEEL_UP)),
		InputBindings.JUMP, "确定 left the input on its old action as well")
	assert_eq(page._working.bindings[InputBindings.ZOOM_IN], [{}, {}], "确定 did not take it from zoom")
	assert_true(page._conflict.is_empty(), "the conflict outlived its answer")

func test_cancelling_a_conflict_changes_nothing() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 0)
	page._input(_key_event(KEY_V))
	_dialog_button(page, "取消").pressed.emit()
	await step(1)
	assert_eq(page._working.bindings, InputBindings.defaults(), "取消 changed a binding")
	assert_true(page._conflict.is_empty(), "取消 left the conflict open")
	assert_true(page._capture.is_empty(), "取消 left the slot capturing")

func test_esc_on_the_conflict_dialog_is_cancel_and_keeps_the_page_open() -> void:
	var page: MeSettingsMenu = await _page()
	watch_signals(page)
	page._begin_capture(InputBindings.JUMP, 0)
	page._input(_key_event(KEY_V))
	page._input(_key_event(KEY_ESCAPE))
	assert_true(page._conflict.is_empty(), "Esc did not answer the conflict")
	assert_eq(page._working.bindings, InputBindings.defaults(), "Esc on the dialog changed a binding")
	assert_signal_not_emitted(page, "closed", "Esc on the dialog closed the settings page")

func test_restoring_default_bindings_does_not_save() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 0)
	page._input(_key_event(KEY_E))
	page._on_reset_bindings_pressed()
	assert_eq(page._working.bindings, InputBindings.defaults(), "恢复默认按键 did not reset the bindings")
	assert_false(FileAccess.file_exists(SettingsStore.path), "恢复默认按键 wrote settings.cfg")

func test_every_action_has_a_row_with_two_slots() -> void:
	var page: MeSettingsMenu = await _page()
	for action in InputBindings.ACTIONS:
		assert_true(page._binding_buttons.has(action.id), "no row for %s" % action.id)
		assert_eq((page._binding_buttons[action.id] as Array).size(), InputBindings.SLOTS,
			"%s does not have two slots" % action.id)

func _scroll_of(node: Node) -> ScrollContainer:
	for child in node.get_children():
		if child is ScrollContainer:
			return child as ScrollContainer
		var found := _scroll_of(child)
		if found != null:
			return found
	return null

func test_capture_shows_a_modal_over_the_page_and_esc_takes_it_down() -> void:
	var page: MeSettingsMenu = await _page()
	page._begin_capture(InputBindings.JUMP, 0)
	assert_not_null(page._capture_overlay, "capture put no modal over the page")
	assert_true(page._capture_overlay.is_visible_in_tree(), "the capture modal is not on screen")
	page._input(_key_event(KEY_ESCAPE))
	assert_null(page._capture_overlay, "Esc left the capture modal up")

func test_a_wheel_notch_in_capture_binds_and_does_not_scroll_the_list() -> void:
	var page: MeSettingsMenu = await _page()
	page._working.bindings[InputBindings.ZOOM_OUT] = [{}, {}]
	var scroll := _scroll_of(page)
	assert_not_null(scroll, "the settings page has no scrolling list")
	scroll.scroll_vertical = 0
	page._begin_capture(InputBindings.JUMP, 1)
	await step(1)
	# Through the real dispatch, over the list, as a player's wheel would be.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel)
	var release := wheel.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release)
	await step(2)
	assert_eq(scroll.scroll_vertical, 0, "the wheel notch being bound also scrolled the list")
	assert_true(InputBindings.same(page._working.bindings[InputBindings.JUMP][1],
		InputBindings.mouse(MOUSE_BUTTON_WHEEL_DOWN)), "the wheel notch was not bound")
	assert_null(page._capture_overlay, "the capture modal stayed up after the binding")
