extends ParkourTest

# The last screen of the tutorial. One thing is asserted, and it is the only
# thing that can go catastrophically wrong: a dead end.

func test_a_key_press_leaves_for_the_main_menu() -> void:
	# A screen with no way off it strands the player at the end of the one
	# path the whole feature exists to complete.
	var screen := ThanksScreen.new()
	add_child_autofree(screen)
	await step(1)
	var requested := [""]
	screen._change_scene = func(path): requested[0] = path

	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	key.echo = false
	screen._unhandled_input(key)
	await step(1)

	assert_eq(requested[0], ThanksScreen.MAIN_MENU_SCENE,
		"the thanks page did not ask for the main menu")

func test_a_second_press_does_not_ask_twice() -> void:
	# The white transition spans several frames, and a second scene change
	# requested underneath one already in flight swaps the tree twice.
	var screen := ThanksScreen.new()
	add_child_autofree(screen)
	await step(1)
	var asked := [0]
	screen._change_scene = func(_path): asked[0] += 1

	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	key.echo = false
	screen._unhandled_input(key)
	screen._unhandled_input(key)
	await step(1)

	assert_eq(asked[0], 1, "the thanks page asked to leave %d times" % asked[0])
