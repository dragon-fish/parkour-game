extends ParkourTest

# The character viewer (scripts/ui/character_showcase.gd): structural
# invariants only -- it builds headless, Esc leaves through the change-scene
# seam, and a chosen index past the clip list is a no-op rather than a crash.
# Whether a body/profile exists is machine-local (profiles/ is untracked),
# so nothing here asserts on the body itself.

func test_showcase_builds_and_esc_returns_to_the_main_menu_via_the_seam() -> void:
	var showcase := CharacterShowcase.new()
	add_child_autofree(showcase)
	await step(2)

	var requested := [""]
	showcase._change_scene = func(path): requested[0] = path

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	esc.echo = false
	showcase._unhandled_input(esc)

	assert_eq(requested[0], CharacterShowcase.MAIN_MENU_SCENE, \
		"Esc did not request the main menu through the change-scene seam")

func test_menu_entry_for_the_showcase_uses_the_seam_too() -> void:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	await step(1)

	var requested := [""]
	menu._change_scene = func(path): requested[0] = path

	menu._on_chosen(1)

	assert_eq(requested[0], MainMenu.SHOWCASE_SCENE, \
		"角色 did not request the showcase scene through the seam")

func test_out_of_range_clip_choice_is_a_no_op() -> void:
	var showcase := CharacterShowcase.new()
	add_child_autofree(showcase)
	await step(2)

	showcase._play_index(999)
	pass_test("an out-of-range chosen index did not crash the viewer")
