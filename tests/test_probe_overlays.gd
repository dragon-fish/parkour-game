extends ParkourTest

# The probe markers draw every frame in front of whatever is being played, so
# what these guard is that they stay OFF until asked for -- and that they are
# reachable once they are, through the same two doors every other overlay uses.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _markers() -> Array[Node]:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	var player: Player = world["player"]
	var grab := GrabMarkers.new()
	grab.name = "GrabMarkers"
	grab.player = player
	add_child_autofree(grab)
	var climb := WallClimbMarkers.new()
	climb.name = "WallClimbMarkers"
	climb.player = player
	add_child_autofree(climb)
	await step(2)
	return [grab, climb]

func test_the_probe_markers_start_off() -> void:
	for marker in await _markers():
		assert_false(marker.overlay_shown(), \
			"%s drew itself over the level without being asked" % marker.name)

func test_f12_brings_them_up_together() -> void:
	var markers := await _markers()
	var press := InputEventKey.new()
	press.physical_keycode = KEY_F12
	press.pressed = true
	for marker in markers:
		marker._unhandled_input(press)
	for marker in markers:
		assert_true(marker.overlay_shown(), "%s ignored F12" % marker.name)
	for marker in markers:
		marker._unhandled_input(press)
	for marker in markers:
		assert_false(marker.overlay_shown(), "%s would not go away again" % marker.name)

func test_the_panel_lists_them_so_they_can_be_found_without_the_key() -> void:
	# A key with no visible affordance is a key nobody knows about. Every
	# other overlay has a checkbox; these are no different.
	var listed: Array[String] = []
	for entry in TuningPanel.DEBUG_OVERLAYS:
		listed.append(entry["node_name"])
	assert_true(listed.has("GrabMarkers"), "the ledge probe has no checkbox")
	assert_true(listed.has("WallClimbMarkers"), "the wall probe has no checkbox")

func test_turning_them_off_takes_the_meshes_with_them() -> void:
	# _process returns early once off, so anything left visible on the frame
	# it was switched off would simply stay on screen forever.
	var markers := await _markers()
	for marker in markers:
		marker.show_overlay(true)
	await step(2)
	for marker in markers:
		marker.show_overlay(false)
	await step(2)
	for marker in markers:
		for child in marker.get_children():
			if child is MeshInstance3D:
				assert_false((child as MeshInstance3D).visible, \
					"%s left a marker on screen after being switched off" % marker.name)
